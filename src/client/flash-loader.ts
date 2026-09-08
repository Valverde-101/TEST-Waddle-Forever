import { App } from "electron";
import fs from "fs";
import path = require("path");
import os = require("os");
import crypto = require("crypto");

const DEFAULT_FLASH_VERSION = '32.0.0.303';

const getPluginName = () => {
  let pluginName: string;

  switch (process.platform) {
    case 'win32':
      switch (process.arch) {
        case 'ia32':
          pluginName = 'assets/flash/pepflashplayer32_32_0_0_303.dll';
          break;

        default:
        case 'x64':
          pluginName = 'assets/flash/pepflashplayer64_32_0_0_303.dll';
          break;
      }
      break;
    case 'darwin':
      pluginName = 'assets/flash/PepperFlashPlayer.plugin';
      break;
    case 'linux':
      pluginName = 'assets/flash/libpepflashplayer.so';
      break;
    default:
      throw new Error(`Unsupported OS for flash: ${process.platform}`);
  }

  return pluginName;
};

const getPluginPath = () => {
  const override = process.env.WADDLE_PPAPI_FLASH_PATH?.trim();
  if (override) {
    return path.resolve(override);
  }
  return path.join(__dirname, '..', getPluginName());
};

const hashFile = (filePath: string) => {
  const bytes = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
};

const getWindowsFlashCacheRoot = () => {
  const localAppData = process.env.LOCALAPPDATA?.trim();
  const base = localAppData || os.tmpdir();
  return path.join(base, 'WaddleForever', 'flash-cache');
};

const prepareRuntimePlugin = (sourcePath: string, flashVersion: string) => {
  const sourceHash = hashFile(sourcePath);

  // Chromium/Electron can execute the application itself from a mapped SMB
  // repository while still refusing to load a PPAPI DLL from that network
  // location. Keep the repository DLL authoritative, but stage exactly that
  // one binary into a hash-addressed local cache before Chromium starts.
  // Electron, node_modules, compiled JS, SWFs and media remain in the repo.
  if (process.platform !== 'win32') {
    return {
      sourcePath,
      runtimePath: sourcePath,
      sha256: sourceHash,
      mode: 'repo_direct',
      copied: false
    };
  }

  const cacheDir = path.join(getWindowsFlashCacheRoot(), flashVersion, sourceHash.toLowerCase());
  fs.mkdirSync(cacheDir, { recursive: true });
  const runtimePath = path.join(cacheDir, path.basename(sourcePath));

  if (path.resolve(runtimePath).toLowerCase() === path.resolve(sourcePath).toLowerCase()) {
    return {
      sourcePath,
      runtimePath,
      sha256: sourceHash,
      mode: 'local_hash_cache',
      copied: false
    };
  }

  let copied = false;
  let runtimeHash = fs.existsSync(runtimePath) ? hashFile(runtimePath) : '';
  if (runtimeHash !== sourceHash) {
    const temporaryPath = `${runtimePath}.${process.pid}.${Date.now()}.tmp`;
    try {
      fs.copyFileSync(sourcePath, temporaryPath);
      const temporaryHash = hashFile(temporaryPath);
      if (temporaryHash !== sourceHash) {
        throw new Error(`Pepper Flash cache verification failed: source=${sourceHash} staged=${temporaryHash}`);
      }
      if (fs.existsSync(runtimePath)) {
        fs.unlinkSync(runtimePath);
      }
      fs.renameSync(temporaryPath, runtimePath);
      copied = true;
    } finally {
      if (fs.existsSync(temporaryPath)) {
        try { fs.unlinkSync(temporaryPath); } catch {}
      }
    }
    runtimeHash = hashFile(runtimePath);
  }

  if (runtimeHash !== sourceHash) {
    throw new Error(`Pepper Flash runtime hash mismatch: source=${sourceHash} runtime=${runtimeHash}`);
  }

  return {
    sourcePath,
    runtimePath,
    sha256: sourceHash,
    mode: 'local_hash_cache',
    copied
  };
};

const loadFlashPlugin = (app: App) => {
  const sourcePath = getPluginPath();
  const flashVersion = process.env.WADDLE_PPAPI_FLASH_VERSION?.trim() || DEFAULT_FLASH_VERSION;

  if (!fs.existsSync(sourcePath)) {
    throw new Error(`Pepper Flash plugin not found: ${sourcePath}`);
  }

  const prepared = prepareRuntimePlugin(sourcePath, flashVersion);
  process.env.WADDLE_PPAPI_FLASH_SOURCE_PATH = prepared.sourcePath;
  process.env.WADDLE_PPAPI_FLASH_RUNTIME_PATH = prepared.runtimePath;

  app.commandLine.appendSwitch('ppapi-flash-path', prepared.runtimePath);
  app.commandLine.appendSwitch('ppapi-flash-version', flashVersion);
  console.log(`WADDLE_PPAPI_FLASH_CONFIG=PASS source=${prepared.sourcePath} runtime=${prepared.runtimePath} version=${flashVersion} sha256=${prepared.sha256} mode=${prepared.mode} copied=${prepared.copied} platform=${process.platform} arch=${process.arch}`);

  return {
    ...prepared,
    version: flashVersion
  };
};

export default loadFlashPlugin;