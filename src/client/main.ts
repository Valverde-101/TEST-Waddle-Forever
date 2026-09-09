import { runtimeDiagnosticPath, writeRuntimeDiagnostic } from './runtime-diagnostics';
import '@common/runtime-node-path';

import { app, BrowserWindow, dialog, Menu, shell } from 'electron';
import log from 'electron-log';
import { startDiscordRPC } from './discord';
import loadFlashPlugin from './flash-loader';
import startMenu from './menu';
import createStore from './store';
import { createWindow } from './window';
import settingsManager from '@server/settings';
import { showWarning } from './warning';
import { setLanguageInStore } from './discord/localization/localization';
import electronIsDev from 'electron-is-dev';
import { AdminError, destroyProgressWindow, progressWindow, startMedia } from './media';
import { GlobalSettings } from '@common/utils';
import { NAME, VERSION, WEBSITE } from '@common/constants';
import { Popups } from './popups';
import { WorldServer } from '@server/socket-server/world-server';
import { startMods, startServices } from '@server/boot';

log.initialize();
console.log = log.log;

writeRuntimeDiagnostic('diagnostics-ready', { path: runtimeDiagnosticPath });

const store = createStore();
const nonInteractive = process.env.WADDLE_NONINTERACTIVE === '1';

setLanguageInStore(store, 'en');
app.setName(NAME);
app.setAboutPanelOptions({
  applicationName: NAME,
  applicationVersion: VERSION,
  website: WEBSITE
});

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

let mainWindow: BrowserWindow;

const globalSettings: GlobalSettings = {
  multiplayer: { type: 'local' }
};

const popups: Popups = new Map<string, BrowserWindow>();

app.once('ready', async () => {
  writeRuntimeDiagnostic('electron-ready', {
    nonInteractive,
    electronIsDev
  });

  if (process.platform === 'darwin') {
    // While setup/media work is running, expose only the native app menu.
    Menu.setApplicationMenu(Menu.buildFromTemplate([{ id: '0', role: 'appMenu' }]));
  }

  try {
    writeRuntimeDiagnostic('media-start-begin', { electronIsDev });
    await startMedia();
    writeRuntimeDiagnostic('media-start-complete', { electronIsDev });
  } catch (error) {
    writeRuntimeDiagnostic('media-start-failed', {
      error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
    });

    if (nonInteractive) {
      destroyProgressWindow();
      app.quit();
      return;
    }

    const win = await progressWindow();
    if (error instanceof AdminError) {
      await dialog.showMessageBox(win, {
        buttons: ['Ok'],
        title: 'Permission Error',
        message: 'Waddle Forever could not initiate the files. Please run Waddle Forever as an administrator to fix this issue.'
      });
    } else {
      const message = error instanceof Error ? `${error.name}:${error.message}\n${error.stack}` : 'Unknown';
      await dialog.showMessageBox(win, {
        buttons: ['Ok'],
        title: 'Download Error',
        message: `It was not possible to finish the installation.\nPlease check your internet connection, and if the problem persists contact the Waddle Forever admins.\n\nShow this to the admins:\n${message}`
      });
    }
    destroyProgressWindow();
    app.quit();
    return;
  }

  const failedMods = startMods();
  if (failedMods.length > 0) {
    writeRuntimeDiagnostic('mods-failed', { mods: failedMods.join(',') });
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
      const win = await progressWindow();
      const result = await dialog.showMessageBox(win, {
        type: 'question',
        buttons: ['Boot Serverless', 'Check out error'],
        title: 'Server Error',
        message: `Another process is already using the designated ports.\n\nIf you want, you can boot Waddle Forever without its server, but this is only useful if you have another Waddle Forever client running already.\n\nSelect 'Boot Serverless' to ignore this error, or check out the error to see the details (this option will terminate the program).`,
        defaultId: 1,
        cancelId: 0
      });

      if (result.response === 1) {
        await showWarning(win, 'Error', error.message + '\n' + error.stack);
        destroyProgressWindow();
        app.quit();
        return;
      }
    } else {
      throw error;
    }
  }

  writeRuntimeDiagnostic('main-window-create-begin');
  mainWindow = await createWindow(store, globalSettings, settingsManager);

  // The upstream media flow reuses one setup/progress window for every phase.
  // Destroy it only after the real game window exists, which also avoids the
  // Windows behavior where closing the last window can terminate Electron.
  destroyProgressWindow();

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

  writeRuntimeDiagnostic('main-window-ready', {
    url: mainWindow.webContents.getURL(),
    flashRuntime: true,
    flashRuntimePath: flashConfig.runtimePath,
    flashMode: flashConfig.mode
  });

  mainWindow.on('closed', () => {
    popups.forEach(win => win.close());
  });

  // User-facing notices are intentionally shown after the certified game window
  // is ready so they cannot block Waddle-Start's health gate.
  if (!settingsManager.settings.faq_warning) {
    if (nonInteractive) {
      settingsManager.updateSettings({ faq_warning: true });
      writeRuntimeDiagnostic('first-run-faq-skipped', { reason: 'noninteractive' });
    } else {
      const result = await dialog.showMessageBox(mainWindow, {
        buttons: ['Take me to the FAQ', 'Understood'],
        title: 'Heads-Up!',
        message: `Welcome to Waddle Forever! If you know nothing about this client, you might be confused about some things:\n- You don't need to create an account, just log in with any name or password\n- The game is entirely offline\n- You can choose the day in the timeline, use commands, and more through the menu\n\nThese are the most important things, but there is a full list of questions in our FAQ. If you're ever lost, you can read it in our website.`,
        cancelId: 1
      });

      if (result.response === 0 || result.response === 1) {
        if (result.response === 0) void shell.openExternal(`${WEBSITE}/faq`);
        settingsManager.updateSettings({ faq_warning: true });
      }
    }
  }

  if (failedMods.length > 0 && !nonInteractive) {
    await dialog.showMessageBox(mainWindow, {
      buttons: ['OK'],
      title: 'Error with Mods',
      message: `The following mods could not be turned on. Please fix them and then try enabling them again:\n\n${failedMods.map(mod => `* ${mod}`).join('\n')}`
    });
  }
});

app.on('window-all-closed', async () => {
  if (process.platform !== 'darwin') {
    try {
      const discordClient = store.private.get('discordState')?.client;
      if (discordClient) await discordClient.destroy();
    } finally {
      writeRuntimeDiagnostic('window-all-closed');
      app.quit();
      process.exit(0);
    }
  }
});

app.on('activate', async () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    mainWindow = await createWindow(store, globalSettings, settingsManager);
    startMenu(store, mainWindow, globalSettings, settingsManager, popups, server);
  }
});
