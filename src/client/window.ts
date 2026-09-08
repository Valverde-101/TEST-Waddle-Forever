import path from 'path';
import { BrowserWindow, shell } from "electron";
import { Store } from "./store";
import { checkUpdates } from "./update";
import { GlobalSettings } from '../common/utils';
import { SettingsManager } from '../server/settings';
import { getSiteUrl } from './views/multiplayer/multiplayer';
import { instrumentRuntimeWindow } from './runtime-diagnostics';
import { installWaddleDiagnosticPanel } from './diagnostic-panel';

export const toggleFullScreen = (store: Store, mainWindow: BrowserWindow) => {
  const fullScreen = !store.private.get("fullScreen");

  store.private.set("fullScreen", fullScreen);

  mainWindow.setFullScreen(fullScreen);
};

export const loadMain = async (window: BrowserWindow, settings: GlobalSettings, serverSettings: SettingsManager): Promise<void> => {
  await window.loadURL(getSiteUrl(settings, serverSettings));
}

interface FiveIconByPlatforms {
  [key: string]: () => void;
}

const isInternalNavigation = (url: string, clientSettings: GlobalSettings, serverSettings: SettingsManager) => {
  try {
    const expected = new URL(getSiteUrl(clientSettings, serverSettings));
    const destination = new URL(url);
    return destination.origin === expected.origin;
  } catch {
    return false;
  }
};

const createWindow = async (store: Store, clientSettings: GlobalSettings, serverSettings: SettingsManager) => {
  // Keep the game window hidden only while its local page is loading. On SMB
  // clients Chromium can otherwise create a nominal BrowserWindow while the
  // renderer/profile is still settling, leaving a background/off-screen window
  // even though the launcher later observes a healthy Flash object.
  const mainWindow = new BrowserWindow({
    width: 1280,
    height: 720,
    show: false,
    title: "Loading...",
    webPreferences: {
      plugins: true,
    },
  });

  // Instrument before loadURL. Attaching after createWindow returned meant the
  // initial Club Penguin HTML/SWF/XML burst had already completed, so the most
  // important boot-time resource requests never reached diagnostics or DevTools.
  instrumentRuntimeWindow(mainWindow, 'main');

  // The in-game diagnostic panel is also registered before loadURL. It consumes
  // the same live trace without altering SWF bytes and can export a sanitized
  // share bundle under .work/diagnostics/share for reproducible support.
  installWaddleDiagnosticPanel(mainWindow);

  const setFaviconByPlatform: FiveIconByPlatforms = {
    win32: () => {
      mainWindow.setIcon(path.join(__dirname, "../assets/favicon.ico"));
    },
    darwin: () => {
      mainWindow.setIcon(path.join(__dirname, "../assets/icon.png"));
    },
    linux: () => {
      mainWindow.setIcon(path.join(__dirname, "../assets/icon.png"));
    },
  };
  
  setFaviconByPlatform[process.platform]();
  
  mainWindow.setMenu(null);

  // Update discovery is advisory. Network/API cleanup errors must never become
  // an unhandled rejection that destabilizes an otherwise fully offline boot.
  void checkUpdates(mainWindow, serverSettings).catch(error => {
    console.warn('Update check failed:', error);
  });

  await loadMain(mainWindow, clientSettings, serverSettings);

  // Presentation is explicit and occurs only after loadURL resolves. center()
  // resets stale/off-screen coordinates from a previous monitor topology, while
  // show/maximize/focus make launcher success correspond to a window the user
  // can actually see instead of merely a live renderer process.
  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }
  mainWindow.center();
  mainWindow.show();
  mainWindow.maximize();
  mainWindow.focus();

  if (!mainWindow.isVisible()) {
    throw new Error('WADDLE_MAIN_WINDOW_PRESENTATION=FAIL window_not_visible_after_show');
  }
  console.log(`WADDLE_MAIN_WINDOW_PRESENTATION=PASS visible=${mainWindow.isVisible()} focused=${mainWindow.isFocused()} minimized=${mainWindow.isMinimized()}`);

  // Only the exact Waddle server origin is allowed to navigate inside the
  // privileged Electron window. The previous substring check required a URL to
  // contain both "localhost" and targetIP (normally 127.0.0.1), so legitimate
  // internal navigation was frequently misclassified as external. Exact origin
  // comparison also avoids treating attacker-controlled hostnames that merely
  // contain a trusted substring as internal.
  const guardNavigation = (event: Electron.Event, url: string) => {
    if (isInternalNavigation(url, clientSettings, serverSettings)) {
      return;
    }

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
