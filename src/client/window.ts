import path from 'path';
import { BrowserWindow, shell } from 'electron';
import { Store } from './store';
import { checkUpdates } from './update';
import { GlobalSettings } from '../common/utils';
import { SettingsManager } from '../server/settings';
import { getSiteUrl } from './views/multiplayer/multiplayer';
import { instrumentRuntimeWindow } from './runtime-diagnostics';
import { installWaddleDiagnosticPanel } from './diagnostic-panel';

const faviconPaths: Record<string, string> = {
  win32: '../assets/favicon.ico',
  darwin: '../assets/icon.png',
  linux: '../assets/icon.png'
};

export const toggleFullScreen = (store: Store, mainWindow: BrowserWindow) => {
  const fullScreen = !store.private.get('fullScreen');
  store.private.set('fullScreen', fullScreen);
  mainWindow.setFullScreen(fullScreen);
};

export const loadMain = async (window: BrowserWindow, settings: GlobalSettings, serverSettings: SettingsManager): Promise<void> => {
  await window.loadURL(getSiteUrl(settings, serverSettings));
};

const isInternalNavigation = (url: string, clientSettings: GlobalSettings, serverSettings: SettingsManager) => {
  try {
    const expected = new URL(getSiteUrl(clientSettings, serverSettings));
    const destination = new URL(url);
    return destination.origin === expected.origin;
  } catch {
    return false;
  }
};

export const createWindow = async (store: Store, clientSettings: GlobalSettings, serverSettings: SettingsManager) => {
  const mainWindow = new BrowserWindow({
    width: 1280,
    height: 720,
    show: false,
    title: 'Loading...',
    webPreferences: {
      plugins: true
    }
  });

  // Must happen before loadURL so the initial SWF/XML/JSON burst is visible.
  instrumentRuntimeWindow(mainWindow, 'main');
  const diagnosticPanelReady = installWaddleDiagnosticPanel(mainWindow);

  const favicon = faviconPaths[process.platform];
  if (favicon !== undefined) {
    mainWindow.setIcon(path.join(__dirname, favicon));
  }

  mainWindow.setMenu(null);

  // Update discovery is advisory. Offline/API errors must not destabilize boot.
  void checkUpdates(mainWindow, serverSettings).catch(error => {
    console.warn('Update check failed:', error);
  });

  await loadMain(mainWindow, clientSettings, serverSettings);
  await diagnosticPanelReady;

  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.center();
  mainWindow.show();
  mainWindow.maximize();
  mainWindow.focus();

  if (!mainWindow.isVisible()) {
    throw new Error('WADDLE_MAIN_WINDOW_PRESENTATION=FAIL window_not_visible_after_show');
  }
  console.log(`WADDLE_MAIN_WINDOW_PRESENTATION=PASS visible=${mainWindow.isVisible()} focused=${mainWindow.isFocused()} minimized=${mainWindow.isMinimized()}`);

  const guardNavigation = (event: Electron.Event, url: string) => {
    if (isInternalNavigation(url, clientSettings, serverSettings)) return;

    event.preventDefault();
    try {
      const destination = new URL(url);
      if (destination.protocol === 'http:' || destination.protocol === 'https:') {
        void shell.openExternal(destination.toString());
      }
    } catch {
      // Invalid/non-URL navigation remains blocked.
    }
  };

  mainWindow.webContents.on('will-navigate', guardNavigation);
  mainWindow.webContents.on('will-redirect', guardNavigation);

  return mainWindow;
};

export default createWindow;
