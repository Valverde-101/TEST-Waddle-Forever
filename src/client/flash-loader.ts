import { App } from "electron";
import fs from "fs";
import path = require("path");

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

const loadFlashPlugin = (app: App) => {
  const pluginPath = getPluginPath();
  const flashVersion = process.env.WADDLE_PPAPI_FLASH_VERSION?.trim() || DEFAULT_FLASH_VERSION;

  if (!fs.existsSync(pluginPath)) {
    throw new Error(`Pepper Flash plugin not found: ${pluginPath}`);
  }

  app.commandLine.appendSwitch('ppapi-flash-path', pluginPath);
  app.commandLine.appendSwitch('ppapi-flash-version', flashVersion);
  console.log(`WADDLE_PPAPI_FLASH_CONFIG=PASS path=${pluginPath} version=${flashVersion} platform=${process.platform} arch=${process.arch}`);
};

export default loadFlashPlugin;