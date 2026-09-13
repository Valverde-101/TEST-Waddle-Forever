import { Router, Request } from 'express';
import { GameData } from '@server/timelines/game-data';
import path from 'path';
import fs from 'fs';
import { MODS_DIRECTORY } from '@common/paths';
import { FileGenerator, getGeneratorsMap, postGeneratorsMap } from '@server/file-generators';
import { MEDIA_DIRECTORY, readFile, toForwardSlash } from '@common/utils';
import { SettingsManager } from '@server/settings';
import { FileOverrider, OVERRIDERS, REGEX_OVERRIDERS } from './overriders';
import { getYellowString, logverbose } from '@server/logger';
import { publishWaddleLiveTrace } from '@common/live-trace';

const CLOTHING_ASSET_ROUTE = /^play\/v2\/content\/global\/clothing\/(?:icons|paper|sprites)\/[^/]+\.swf$/i;
const CLOTHING_MEMORY_CACHE_MAX_BYTES = 96 * 1024 * 1024;
const CLOTHING_MEMORY_CACHE_MAX_ENTRIES = 1536;
const CLOTHING_HTTP_CACHE_SECONDS = 300;

const normalizeRequestRoute = (rawRoute: string): string | undefined => {
  if (rawRoute.includes('\0')) return undefined;

  const route = toForwardSlash(rawRoute);
  if (route.startsWith('/') || /^[A-Za-z]:\//.test(route)) return undefined;
  const segments = route.split('/');
  if (segments.some(segment => segment === '.' || segment === '..')) return undefined;
  return route;
};

const resolveWithinRoot = (root: string, ...parts: string[]): string | undefined => {
  const normalizedRoot = path.resolve(root);
  const candidate = path.resolve(normalizedRoot, ...parts);
  const prefix = normalizedRoot.endsWith(path.sep) ? normalizedRoot : normalizedRoot + path.sep;
  if (candidate === normalizedRoot || candidate.startsWith(prefix)) return candidate;
  return undefined;
};

const getAssetKind = (route: string) => {
  const clean = route.split('?')[0];
  const extension = path.extname(clean).replace(/^\./, '').toUpperCase();
  return extension || 'ROUTE';
};

const isClothingAssetRoute = (route: string) => CLOTHING_ASSET_ROUTE.test(route);

const traceFileResolution = (
  route: string,
  phase: 'handled' | 'error',
  status: string,
  detail: Record<string, unknown> = {}
) => {
  publishWaddleLiveTrace({
    category: 'FILE',
    phase,
    source: 'file-server',
    action: route,
    status,
    assetKind: getAssetKind(route),
    ...detail
  });
};

/** Server that serves files to the game webpage and files in the game */
export class FileServer {
  private modFiles = new Map<string, string>();
  private overrider: FileOverrider;
  private dynamicFiles: Map<string, FileGenerator>;
  private postGenerators: Map<string, FileGenerator>;
  private clothingMemoryCache = new Map<string, Buffer>();
  private clothingMemoryCacheBytes = 0;
  private clothingReadsInFlight = new Map<string, Promise<Buffer>>();

  constructor(private gameData: GameData, private settings: SettingsManager) {
    this.dynamicFiles = getGeneratorsMap();
    this.postGenerators = postGeneratorsMap();

    this.updateModFiles();
    settings.mods.addListener(() => this.updateModFiles());

    // Upstream regex overriders are required for chat[n].swf 30-FPS handling.
    this.overrider = new FileOverrider(gameData, settings, OVERRIDERS, REGEX_OVERRIDERS);
  }

  private clearClothingMemoryCache() {
    this.clothingMemoryCache.clear();
    this.clothingMemoryCacheBytes = 0;
    this.clothingReadsInFlight.clear();
  }

  private getClothingCacheKey(filePath: string) {
    const absolute = path.resolve(filePath);
    return process.platform === 'win32' ? absolute.toLowerCase() : absolute;
  }

  private rememberClothingAsset(cacheKey: string, binary: Buffer) {
    if (binary.length > CLOTHING_MEMORY_CACHE_MAX_BYTES) return;

    const previous = this.clothingMemoryCache.get(cacheKey);
    if (previous !== undefined) {
      this.clothingMemoryCacheBytes -= previous.length;
      this.clothingMemoryCache.delete(cacheKey);
    }

    this.clothingMemoryCache.set(cacheKey, binary);
    this.clothingMemoryCacheBytes += binary.length;

    while (
      this.clothingMemoryCache.size > CLOTHING_MEMORY_CACHE_MAX_ENTRIES ||
      this.clothingMemoryCacheBytes > CLOTHING_MEMORY_CACHE_MAX_BYTES
    ) {
      const oldest = this.clothingMemoryCache.keys().next();
      if (oldest.done || oldest.value === undefined) break;
      const stale = this.clothingMemoryCache.get(oldest.value);
      this.clothingMemoryCache.delete(oldest.value);
      if (stale !== undefined) this.clothingMemoryCacheBytes -= stale.length;
    }
  }

  private async readResolvedFile(route: string, filePath: string): Promise<Buffer> {
    if (!isClothingAssetRoute(route)) return await readFile(filePath);

    const cacheKey = this.getClothingCacheKey(filePath);
    const cached = this.clothingMemoryCache.get(cacheKey);
    if (cached !== undefined) {
      // Refresh insertion order so the bounded Map behaves as an LRU cache.
      this.clothingMemoryCache.delete(cacheKey);
      this.clothingMemoryCache.set(cacheKey, cached);
      return cached;
    }

    const pending = this.clothingReadsInFlight.get(cacheKey);
    if (pending !== undefined) return await pending;

    const load = readFile(filePath)
      .then(binary => {
        this.rememberClothingAsset(cacheKey, binary);
        return binary;
      })
      .finally(() => {
        this.clothingReadsInFlight.delete(cacheKey);
      });

    this.clothingReadsInFlight.set(cacheKey, load);
    return await load;
  }

  private updateModFiles() {
    // A mod can replace a clothing SWF without changing its request URL. Drop the
    // session cache whenever the active mod set changes so no stale asset survives.
    this.clearClothingMemoryCache();
    this.modFiles = new Map<string, string>();
    for (const mod of this.settings.mods.getActiveMods()) {
      mod.getFiles().forEach(file => {
        const route = normalizeRequestRoute(toForwardSlash(file));
        if (route === undefined) {
          console.warn(`Ignoring unsafe mod file route from ${mod.getName()}: ${file}`);
          traceFileResolution(String(file), 'error', 'unsafe-mod-route', { mod: mod.getName() });
          return;
        }
        this.modFiles.set(route, mod.getName());
      });
    }
  }

  private async getFile(route: string): Promise<Buffer | string | undefined> {
    let filePath: string | undefined;
    const modName = this.modFiles.get(route);

    if (modName !== undefined) {
      logverbose(getYellowString(`requesting ${route}, sending MODDED file`));
      filePath = resolveWithinRoot(MODS_DIRECTORY, modName, route);
      if (filePath === undefined) {
        console.warn(`Blocked mod path outside managed root: mod=${modName} route=${route}`);
        traceFileResolution(route, 'error', 'unsafe-mod-target', { mod: modName });
        return undefined;
      }
      traceFileResolution(route, 'handled', 'resolved-mod', {
        resolver: 'mod',
        mod: modName,
        target: toForwardSlash(path.join(modName, route))
      });
    } else {
      const lookup = this.gameData.lookupFile(route);
      if (lookup !== undefined) {
        const relativeFile = typeof lookup === 'string' ? lookup : lookup(this.settings);
        logverbose(`req ${route} -> send ${relativeFile}`);
        filePath = resolveWithinRoot(MEDIA_DIRECTORY, relativeFile);
        if (filePath === undefined) {
          console.warn(`Blocked game-data path outside media root: route=${route} target=${relativeFile}`);
          traceFileResolution(route, 'error', 'unsafe-game-data-target', {
            resolver: 'game-data',
            target: toForwardSlash(String(relativeFile))
          });
          return undefined;
        }
        traceFileResolution(route, 'handled', 'resolved-game-data', {
          resolver: 'game-data',
          target: toForwardSlash(String(relativeFile)),
          memoryCacheEligible: isClothingAssetRoute(route)
        });
      }
    }

    if (filePath === undefined) {
      const generator = this.dynamicFiles.get(route);
      if (generator !== undefined) {
        traceFileResolution(route, 'handled', 'resolved-dynamic', { resolver: 'dynamic-generator' });
        return generator(this.gameData, this.settings);
      }
    } else {
      try {
        return await this.readResolvedFile(route, filePath);
      } catch (error) {
        traceFileResolution(route, 'error', 'read-failed', {
          resolver: modName !== undefined ? 'mod' : 'game-data',
          error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
        });
        throw error;
      }
    }

    const websiteRoot = resolveWithinRoot(MEDIA_DIRECTORY, 'default', 'websites', this.gameData.getWebsite());
    if (websiteRoot === undefined) {
      traceFileResolution(route, 'error', 'unsafe-website-root', {
        resolver: 'website',
        website: this.gameData.getWebsite()
      });
      throw new Error(`Website root escaped media directory: ${this.gameData.getWebsite()}`);
    }

    const websiteFile = resolveWithinRoot(websiteRoot, route);
    if (websiteFile !== undefined && fs.existsSync(websiteFile) && fs.statSync(websiteFile).isFile()) {
      traceFileResolution(route, 'handled', 'resolved-website', {
        resolver: 'website',
        website: this.gameData.getWebsite(),
        target: toForwardSlash(path.relative(MEDIA_DIRECTORY, websiteFile))
      });
      return await readFile(websiteFile);
    }

    traceFileResolution(route, 'error', 'not-found', {
      resolver: 'none',
      website: this.gameData.getWebsite()
    });
    return undefined;
  }

  public getExpressRouter(): Router {
    const router = Router();

    router.get('/*', async (req: Request, res, next) => {
      let route: string | undefined;
      try {
        route = normalizeRequestRoute(req.params[0]);
        if (route === undefined) {
          traceFileResolution(String(req.params[0] ?? ''), 'error', 'invalid-route', { method: 'GET' });
          res.status(400).send('Invalid file route');
          return;
        }

        const binary = await this.getFile(route);
        if (binary === undefined) {
          next();
          return;
        }

        const split = route.split('.');
        const type = split.length < 2 ? '.html' : split.pop();
        if (type === undefined) throw new Error('Split somehow returned empty list');

        const value = await this.overrider.override(route, binary);
        if (isClothingAssetRoute(route)) {
          // The legacy Flash client frequently reconstructs the inventory grid and
          // asks for the same icon/paper/sprite SWFs again. Keep a short browser
          // freshness window while the server-side LRU removes repeated SMB reads.
          res.set('Cache-Control', `public, max-age=${CLOTHING_HTTP_CACHE_SECONDS}`);
          res.set('X-Waddle-Asset-Cache', 'clothing-memory-lru');
        }
        res.status(200).type(type).send(value);
      } catch (error) {
        if (route !== undefined) {
          traceFileResolution(route, 'error', 'serve-failed', {
            method: 'GET',
            error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
          });
        }
        next(error);
      }
    });

    router.post('/*', (req: Request, res, next) => {
      const route = normalizeRequestRoute(req.params[0]);
      if (route === undefined) {
        traceFileResolution(String(req.params[0] ?? ''), 'error', 'invalid-route', { method: 'POST' });
        res.status(400).send('Invalid generator route');
        return;
      }

      const generator = this.postGenerators.get(route);
      if (generator === undefined) {
        traceFileResolution(route, 'error', 'post-generator-not-found', { method: 'POST' });
        next();
      } else {
        traceFileResolution(route, 'handled', 'resolved-post-generator', {
          method: 'POST',
          resolver: 'post-generator'
        });
        res.send(generator(this.gameData, this.settings));
      }
    });

    return router;
  }
}
