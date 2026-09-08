import { instrumentRuntimeWindow, runtimeDiagnosticPath, writeRuntimeDiagnostic } from './runtime-diagnostics';
import '@common/runtime-node-path';
import path from 'path'

import { app, BrowserWindow, dialog, shell } from "electron";
import log from "electron-log";
import { startDiscordRPC } from "./discord";
import loadFlashPlugin from "./flash-loader";
import startMenu from "./menu";
import createStore from "./store";
import createWindow from "./window";
import settingsManager from "@server/settings";
import { showWarning } from "./warning";
import electronIsDev from "electron-is-dev";
import { AdminError, downloadMediaFolder, startMedia } from "./media";
import { GlobalSettings } from '@common/utils';
import { VERSION } from '@common/version';
import { Popups } from './popups';
import { WEBSITE } from '@common/website';
import { WorldServer } from '@server/socket-server/world-server';
import { startMods, startServices } from '@server/boot';

log.initialize();

console.log = log.log;

writeRuntimeDiagnostic('diagnostics-ready', { path: runtimeDiagnosticPath });

const store = createStore();
const nonInteractive = process.env.WADDLE_NONINTERACTIVE === '1';

if (process.platform === 'linux') {
  app.commandLine.appendSwitch('no-sandbox');
}

let server: WorldServer | null = null;

const flashConfig = loadFlashPlugin(app);

type FlashRuntimeStatus = {
  pluginFound: boolean;
  pluginName: string;
  pluginFilename: string;
  mimeFound: boolean;
  mimeType: string;
  objectPresent: boolean;
  scriptable: boolean;
  fallbackPresent: boolean;
  readyState: string;
};

const wait = (milliseconds: number) => new Promise<void>(resolve => setTimeout(resolve, milliseconds));

const readFlashRuntimeStatus = async (window: BrowserWindow): Promise<FlashRuntimeStatus> => {
  const result = await window.webContents.executeJavaScript(`(() => {
    const plugins = [];
    for (let i = 0; i < navigator.plugins.length; i += 1) {
      const plugin = navigator.plugins[i];
      plugins.push({
        name: plugin.name || '',
        filename: plugin.filename || '',
        description: plugin.description || ''
      });
    }
    const flash = plugins.find(plugin => /shockwave flash|pepperflash|flash player/i.test(
      plugin.name + ' ' + plugin.filename + ' ' + plugin.description
    ));
    const mime = navigator.mimeTypes && navigator.mimeTypes.namedItem
      ? navigator.mimeTypes.namedItem('application/x-shockwave-flash')
      : null;
    const documents = [document];
    for (let i = 0; i < window.frames.length; i += 1) {
      try {
        const childDocument = window.frames[i].document;
        if (childDocument) documents.push(childDocument);
      } catch (_) {}
    }
    let object = null;
    let fallbackPresent = false;
    for (const currentDocument of documents) {
      if (!object) {
        object = currentDocument.querySelector(
          'object[type="application/x-shockwave-flash"], embed[type="application/x-shockwave-flash"], object[data*=".swf"], embed[src*=".swf"]'
        );
      }
      const text = currentDocument.body ? currentDocument.body.innerText || '' : '';
      if (/download the free flash player now|latest version of the adobe flash player/i.test(text)) {
        fallbackPresent = true;
      }
    }
    const scriptable = Boolean(object && (
      typeof object.PercentLoaded === 'function' ||
      typeof object.SetVariable === 'function' ||
      typeof object.GetVariable === 'function'
    ));
    return {
      pluginFound: Boolean(flash),
      pluginName: flash ? flash.name : '',
      pluginFilename: flash ? flash.filename : '',
      mimeFound: Boolean(mime),
      mimeType: mime ? mime.type : '',
      objectPresent: Boolean(object),
      scriptable,
      fallbackPresent,
      readyState: document.readyState
    };
  })()`, true) as FlashRuntimeStatus;

  return result;
};

const waitForFlashRuntime = async (window: BrowserWindow, timeoutMs = 25000): Promise<FlashRuntimeStatus> => {
  const deadline = Date.now() + timeoutMs;
  let lastStatus: FlashRuntimeStatus | null = null;
  let reloadedAfterPluginDetection = false;
  let lastError = '';

  while (Date.now() < deadline) {
    if (window.isDestroyed() || window.webContents.isDestroyed()) {
      throw new Error('Main window was destroyed before Flash became ready');
    }

    try {
      const status = await readFlashRuntimeStatus(window);
      lastStatus = status;

      if (status.pluginFound && status.mimeFound && status.objectPresent && !status.fallbackPresent) {
        return status;
      }

      // PPAPI is registered at process startup, but on slow/network-backed
      // launches the page can finish its old SWFObject feature test before the
      // plugin enumeration has settled. Reload exactly once after the plugin is
      // visible so the page can replace its fallback with the real SWF object.
      if (status.pluginFound && status.mimeFound && status.fallbackPresent && !reloadedAfterPluginDetection) {
        reloadedAfterPluginDetection = true;
        writeRuntimeDiagnostic('flash-runtime-reload', {
          reason: 'plugin_visible_after_page_fallback',
          pluginName: status.pluginName,
          pluginFilename: status.pluginFilename
        });
        window.webContents.reload();
        await wait(750);
        continue;
      }
    } catch (error) {
      lastError = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    }

    await wait(250);
  }

  throw new Error(`Flash runtime did not become usable within ${timeoutMs}ms; status=${JSON.stringify(lastStatus)} lastError=${lastError}`);
};

// Keep a global reference of the window object, if you don't, the window will
// be closed automatically when the JavaScript object is garbage collected.
let mainWindow: BrowserWindow;

/** An object to keep global variables in memory across windows */
const globalSettings : GlobalSettings = {
  multiplayer: { type: 'local' }
};

const popups: Popups = new Map<string, BrowserWindow>();

app.on('ready', async () => {
  writeRuntimeDiagnostic('electron-ready', {
    nonInteractive,
    electronIsDev
  });

  // A real window must exist while first-run media/setup work is in progress.
  // mainWindow is deliberately created only after services are ready, so every
  // dialog in this phase must be parented to setupWindow rather than referencing
  // mainWindow before it has been assigned.
  const setupWindow = new BrowserWindow({
    width: 200,
    height: 100,
    frame: false,
    resizable: false
  });
  instrumentRuntimeWindow(setupWindow, 'setup');
  await setupWindow.loadFile(path.join(__dirname, 'views/setup.html'));
  writeRuntimeDiagnostic('setup-window-ready', { nonInteractive });

  try {
    // this will throw an error if installing for all users and not running as
    // an administrator
    writeRuntimeDiagnostic('media-start-begin', { electronIsDev });
    await startMedia();
    writeRuntimeDiagnostic('media-start-complete', { electronIsDev });
  } catch (error) {
    writeRuntimeDiagnostic('media-start-failed', {
      error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
    });

    if (nonInteractive) {
      app.quit();
      return;
    }

    if (error instanceof AdminError) {
      await dialog.showMessageBox(setupWindow, {
        buttons: ['Ok'],
        title: 'Permission Error',
        message: 'Waddle Forever could not initiate the files. Please run Waddle Forever as an administrator to fix this issue.'
      });
      app.quit();
      return;
    } else {
      const message = error instanceof Error ? `${error.name}:${error.message}\n${error.stack}` : 'Unknown';
      await dialog.showMessageBox(setupWindow, {
        buttons: ['Ok'],
        title: 'Download Error',
        message: `It was not possible to finish the installation.\nPlease check your internet connection, and if the problem persists contact the Waddle Forever admins.\n\nShow this to the admins:\n${message}`
      })
  
      app.quit();
      return;
    }
  }
  
  // only check if the clothing settings is false, otherwise it would have been downloaded already
  if (!settingsManager.settings.clothing && settingsManager.settings.answered_packages !== VERSION) {
    if (nonInteractive) {
      settingsManager.updateSettings({ answered_packages: VERSION });
      writeRuntimeDiagnostic('first-run-clothing-skipped', {
        reason: 'noninteractive',
        version: VERSION
      });
    } else {
      const result = await dialog.showMessageBox(setupWindow, {
        buttons: ['Download Clothing (~600 MB)', 'No Thanks'],
        title: 'Download package?',
        message: 'Would you like to download the clothing package? It includes all non essential clothing items from Club Penguin. If you say no, you can always download it later.',
        defaultId: 0,
        cancelId: 1
      });

      if (result.response === 0) {
        let clothingError: unknown;
        const installed = await downloadMediaFolder('clothing', () => {
          settingsManager.updateSettings({ clothing: true });
        }, error => {
          clothingError = error;
        });

        if (installed) {
          settingsManager.updateSettings({ answered_packages: VERSION });
        } else {
          const detail = clothingError instanceof Error ? clothingError.message : String(clothingError ?? 'Unknown error');
          writeRuntimeDiagnostic('optional-clothing-download-failed', { detail });
          await dialog.showMessageBox(setupWindow, {
            buttons: ['OK'],
            title: 'Clothing Download Failed',
            message: `The optional clothing package could not be installed. Waddle Forever will continue without it and offer the download again next time.\n\n${detail}`
          });
        }
      } else {
        settingsManager.updateSettings({ answered_packages: VERSION });
      }
    }
  }

  if (!settingsManager.settings.faq_warning) {
    if (nonInteractive) {
      settingsManager.updateSettings({ faq_warning: true });
      writeRuntimeDiagnostic('first-run-faq-skipped', { reason: 'noninteractive' });
    } else {
      const result = await dialog.showMessageBox(setupWindow, {
        buttons: ['Take me to the FAQ', 'Understood'],
        title: 'Heads-Up!',
        message: `Welcome to Waddle Forever! If you know nothing about this client, you might be confused about some things:
- You don't need to create an account, just log in with any name or password
- The game is entirely offline
- You can choose the day in the timeline, use commands, and more through the menu

These are the most important things, but there is a full list of questions in our FAQ. If you're ever lost, you can read it in our website.`,
        cancelId: 1
      });

      if (result.response === 0 || result.response === 1) {
        if (result.response === 0) {
          void shell.openExternal(`${WEBSITE}/faq`);
        }
        settingsManager.updateSettings({ faq_warning: true });
      }
    }
  }

  const failedMods = startMods();
  if (failedMods.length > 0) {
    writeRuntimeDiagnostic('mods-failed', { mods: failedMods.join(',') });
    if (!nonInteractive) {
      await dialog.showMessageBox(setupWindow, {
        buttons: ['OK'],
        title: 'Error with Mods',
        message: `The following mods could not be turned on. Please fix them and then try enabling them again:\n\n${failedMods.map(mod => `* ${mod}`).join('\n')}`
      });
    }
  }

  try {
    writeRuntimeDiagnostic('services-start-begin');
    server = await startServices();
    writeRuntimeDiagnostic('services-started');
  } catch (error) {
    writeRuntimeDiagnostic('services-start-failed', {
      error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
    });

    if (nonInteractive) {
      throw error;
    }

    if (error instanceof Error && error.message.includes('EADDRINUSE')) {
      const result = await dialog.showMessageBox(setupWindow, {
        buttons: ['Boot Serverless', 'Check out error'],
        title: 'Server Error',
        message: `Another process is already using the designated ports. If you want, you can boot Waddle Forever without its server, but this is only useful if you have another Waddle Forever client running already, otherwise you may have to close the other process using the ports (check error).`,
        defaultId: 1,
        cancelId: 0
      });
      
      if (result.response === 1) {
        await showWarning(setupWindow, 'Error', error.message + '\n' + error.stack);
      }
    } else {
      throw error;
    }
  }

  writeRuntimeDiagnostic('main-window-create-begin');
  mainWindow = await createWindow(store, globalSettings, settingsManager);
  instrumentRuntimeWindow(mainWindow, 'main');
  setupWindow.close();

  // Some users were reporting problems with cache.
  await mainWindow.webContents.session.clearHostResolverCache();

  startMenu(store, mainWindow, globalSettings, settingsManager, popups, server);

  if (!electronIsDev) {
    startDiscordRPC(store, mainWindow);
  }

  try {
    const flashRuntime = await waitForFlashRuntime(mainWindow);
    writeRuntimeDiagnostic('flash-runtime-ready', {
      pluginName: flashRuntime.pluginName,
      pluginFilename: flashRuntime.pluginFilename,
      mimeType: flashRuntime.mimeType,
      objectPresent: flashRuntime.objectPresent,
      scriptable: flashRuntime.scriptable,
      sourcePath: flashConfig.sourcePath,
      runtimePath: flashConfig.runtimePath,
      sha256: flashConfig.sha256,
      mode: flashConfig.mode,
      copied: flashConfig.copied,
      url: mainWindow.webContents.getURL()
    });
  } catch (error) {
    writeRuntimeDiagnostic('flash-runtime-missing', {
      error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
      sourcePath: flashConfig.sourcePath,
      runtimePath: flashConfig.runtimePath,
      sha256: flashConfig.sha256,
      mode: flashConfig.mode,
      copied: flashConfig.copied,
      url: mainWindow.webContents.getURL()
    });
    throw error;
  }

  // This is intentionally emitted only after the real Club Penguin window has
  // a registered Flash plugin, Flash MIME type and instantiated SWF object.
  // Waddle-Start uses this event as its final health gate.
  writeRuntimeDiagnostic('main-window-ready', {
    url: mainWindow.webContents.getURL(),
    flashRuntime: true,
    flashRuntimePath: flashConfig.runtimePath,
    flashMode: flashConfig.mode
  });

  mainWindow.on('closed', () => {
    popups.forEach(win => {
      win.close();
    });
  });
});


app.on('window-all-closed', async () => {
  // On macOS it is common for applications and their menu bar to stay active
  // until the user quits explicitly with Cmd + Q.
  if (process.platform !== 'darwin') {
    try
    {
      const discordClient = store.private.get('discordState')?.client;

      if (discordClient) {
        await discordClient.destroy();
      }
    }
    finally
    {
      writeRuntimeDiagnostic('window-all-closed');
      // Always try to quit
      app.quit();

      process.exit(0);
    }    
  }
});

app.on('activate', async () => {
  // On macOS it's common to re-create a window when the
  // dock icon is clicked and there are no windows open.
  if (BrowserWindow.getAllWindows().length === 0) {
    mainWindow = await createWindow(store, globalSettings, settingsManager);
    instrumentRuntimeWindow(mainWindow, 'main-reactivated');
    startMenu(store, mainWindow, globalSettings, settingsManager, popups, server);
  }
});