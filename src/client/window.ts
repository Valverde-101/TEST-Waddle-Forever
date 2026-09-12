import path from 'path';
import { BrowserWindow, shell } from 'electron';
import { Store } from './store';
import { checkUpdates } from './update';
import { GlobalSettings } from '../common/utils';
import { SettingsManager } from '../server/settings';
import { getSiteUrl } from './views/multiplayer/multiplayer';
import { instrumentRuntimeWindow, writeRuntimeDiagnostic } from './runtime-diagnostics';
import { installWaddleDiagnosticPanel } from './diagnostic-panel';
import { installLegacyWebCompatibility } from './legacy-web-compat';

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

  // Network/live-trace instrumentation remains active before navigation so the
  // initial SWF/XML/JSON burst is never lost.
  instrumentRuntimeWindow(mainWindow, 'main');

  const favicon = faviconPaths[process.platform];
  if (favicon !== undefined) {
    mainWindow.setIcon(path.join(__dirname, favicon));
  }

  mainWindow.setMenu(null);

  // Navigation protection must be in place before the first load starts. This
  // keeps the early-return startup path just as strict as the old awaited path.
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

  // main.ts validates Flash with executeJavaScript(). Electron 10 can leave an
  // executeJavaScript call queued until the renderer has a DOM when navigation
  // is still pending (the legacy Flash page may never reach did-finish-load).
  // Returning the BrowserWindow before dom-ready therefore created a deadlock:
  // the visible page existed, but the Flash probe never completed and the
  // external Play watchdog eventually killed an otherwise healthy client.
  // Resolve only the DOM milestone here; full page completion remains
  // intentionally non-blocking.
  let resolveDomReady: (() => void) | null = null;
  const domReady = new Promise<void>(resolve => {
    resolveDomReady = resolve;
  });

  // The legacy Flash page can keep Electron's loadURL()/did-finish-load
  // lifecycle pending for a long time even though the local HTTP server is
  // already serving the document successfully. Presentation is therefore
  // decoupled from full document completion.
  void loadMain(mainWindow, clientSettings, serverSettings).then(() => {
    writeRuntimeDiagnostic('main-navigation-complete', {
      url: mainWindow.webContents.getURL()
    });
  }).catch(error => {
    writeRuntimeDiagnostic('main-navigation-failed', {
      error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
      url: mainWindow.isDestroyed() || mainWindow.webContents.isDestroyed()
        ? ''
        : mainWindow.webContents.getURL()
    });
  });

  // Diagnostics and compatibility hooks must never be allowed to prevent the
  // game window from opening. Resolve domReady first, then install both hooks
  // strictly best-effort. The compatibility layer restores the dynamic local
  // port for archived AJAX code that incorrectly uses location.hostname.
  mainWindow.webContents.once('dom-ready', () => {
    writeRuntimeDiagnostic('renderer-dom-ready', {
      url: mainWindow.webContents.getURL()
    });
    if (resolveDomReady !== null) {
      resolveDomReady();
      resolveDomReady = null;
    }

    void installLegacyWebCompatibility(mainWindow).catch(error => {
      writeRuntimeDiagnostic('legacy-web-compat-nonblocking-failure', {
        error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
        url: mainWindow.isDestroyed() || mainWindow.webContents.isDestroyed()
          ? ''
          : mainWindow.webContents.getURL()
      });
    });

    void installWaddleDiagnosticPanel(mainWindow).catch(error => {
      writeRuntimeDiagnostic('diagnostic-panel-nonblocking-failure', {
        error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
        url: mainWindow.isDestroyed() || mainWindow.webContents.isDestroyed()
          ? ''
          : mainWindow.webContents.getURL()
      });
    });
  });

  // Update discovery is advisory. Offline/API errors must not destabilize boot.
  void checkUpdates(mainWindow, serverSettings).catch(error => {
    console.warn('Update check failed:', error);
  });

  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.center();
  mainWindow.show();
  mainWindow.maximize();
  mainWindow.focus();

  if (!mainWindow.isVisible()) {
    throw new Error('WADDLE_MAIN_WINDOW_PRESENTATION=FAIL window_not_visible_after_show');
  }
  console.log(`WADDLE_MAIN_WINDOW_PRESENTATION=PASS visible=${mainWindow.isVisible()} focused=${mainWindow.isFocused()} minimized=${mainWindow.isMinimized()}`);
  writeRuntimeDiagnostic('main-window-presented', {
    visible: mainWindow.isVisible(),
    focused: mainWindow.isFocused(),
    minimized: mainWindow.isMinimized(),
    navigationPending: mainWindow.webContents.isLoading()
  });

  const domTimeoutMs = 30000;
  let domTimer: NodeJS.Timeout | null = null;
  try {
    await Promise.race([
      domReady,
      new Promise<void>((_, reject) => {
        domTimer = setTimeout(() => reject(new Error(`WADDLE_RENDERER_DOM_READY_TIMEOUT=${domTimeoutMs}`)), domTimeoutMs);
      })
    ]);
  } finally {
    if (domTimer !== null) clearTimeout(domTimer);
  }

  writeRuntimeDiagnostic('main-window-dom-gate-pass', {
    url: mainWindow.webContents.getURL(),
    loading: mainWindow.webContents.isLoading()
  });

  return mainWindow;
};

export default createWindow;
