import { Router, Request } from 'express';
import { GameData } from '@server/timelines/game-data';
import path from 'path';
import fs from 'fs';
import { MODS_DIRECTORY } from '@common/paths';
import { FileGenerator, getGeneratorsMap, postGeneratorsMap } from '@server/file-generators';
import { MEDIA_DIRECTORY, readFile, toForwardSlash } from '@common/utils';
import { SettingsManager } from '@server/settings';
import { FileOverrider, OVERRIDERS } from './overriders';
import { getYellowString, logverbose } from '@server/logger';

const normalizeRequestRoute = (rawRoute: string): string | undefined => {
  if (rawRoute.includes('\0')) return undefined;

  const route = toForwardSlash(rawRoute);
  // Express normally removes the leading slash from req.params[0], but reject
  // absolute/UNC/drive-qualified inputs here as a second boundary. Reject dot
  // segments instead of normalizing them so traversal attempts are observable
  // failures rather than aliases for a different file.
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

/** Server that serves files to the game webpage and files in the game */
export class FileServer {
  /** Maps file route -> name of the mod that is using this route */
  private modFiles = new Map<string, string>();

  private overrider: FileOverrider;

  private dynamicFiles: Map<string, FileGenerator>

  private postGenerators: Map<string, FileGenerator>

  constructor(private gameData: GameData, private settings: SettingsManager) {
    this.dynamicFiles = getGeneratorsMap();
    this.postGenerators = postGeneratorsMap();

    this.updateModFiles();
    settings.mods.addListener(() => {
      this.updateModFiles();
    });

    // todo remove global state
    this.overrider = new FileOverrider(gameData, settings, OVERRIDERS);
  }

  private updateModFiles() {
    this.modFiles = new Map<string, string>();
    for (const mod of this.settings.mods.getActiveMods()) {
      mod.getFiles().forEach(file => {
        const route = normalizeRequestRoute(toForwardSlash(file));
        if (route === undefined) {
          console.warn(`Ignoring unsafe mod file route from ${mod.getName()}: ${file}`);
          return;
        }
        this.modFiles.set(route, mod.getName());
      })        
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
        return undefined;
      }
    } else {
      const lookup = this.gameData.lookupFile(route);
      if (lookup !== undefined) {
        const relativeFile = typeof lookup === 'string' ? lookup : lookup(this.settings);
        logverbose(`req ${route} -> send ${relativeFile}`);
        filePath = resolveWithinRoot(MEDIA_DIRECTORY, relativeFile);
        if (filePath === undefined) {
          console.warn(`Blocked game-data path outside media root: route=${route} target=${relativeFile}`);
          return undefined;
        }
      }
    }

    if (filePath === undefined) {
      const generator = this.dynamicFiles.get(route);
      if (generator !== undefined) {
        return generator(this.gameData, this.settings);
      }
    } else {
      return await readFile(filePath);
    }

    const websiteRoot = resolveWithinRoot(MEDIA_DIRECTORY, 'default', 'websites', this.gameData.getWebsite());
    if (websiteRoot === undefined) {
      throw new Error(`Website root escaped media directory: ${this.gameData.getWebsite()}`);
    }
    const websiteFile = resolveWithinRoot(websiteRoot, route);
    if (websiteFile !== undefined && fs.existsSync(websiteFile) && fs.statSync(websiteFile).isFile()) {
      return await readFile(websiteFile);
    }

    return undefined;
  }

  public getExpressRouter(): Router {
    const router = Router();

    // generic files (swfs, json, etc.)
    router.get('/*', async (req: Request, res, next) => {
      try {
        const route = normalizeRequestRoute(req.params[0]);
        if (route === undefined) {
          res.status(400).send('Invalid file route');
          return;
        }

        const binary = await this.getFile(route);
        if (binary === undefined) {
          next();
          return;
        }

        const split = route.split('.');
        // if less than 1, then there was no file extension
        // route with no file extension -> a GET request for an HTML file
        const type = split.length < 2 ? '.html' : split.pop();
        if (type === undefined) {
          throw new Error('Split somehow returned empty list');
        }

        const value = await this.overrider.override(route, binary);
        res.status(200).type(type).send(value);
      } catch (error) {
        next(error);
      }
    });
    router.post('/*', (req: Request, res, next) => {
      const route = normalizeRequestRoute(req.params[0]);
      if (route === undefined) {
        res.status(400).send('Invalid generator route');
        return;
      }

      const generator = this.postGenerators.get(route);
      if (generator === undefined) {
        next();
      } else {
        res.send(generator(this.gameData, this.settings));
      }
    });

    return router;
  }
}