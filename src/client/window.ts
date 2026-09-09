import path from 'path';
import { BrowserWindow, shell } from 'electron';
import { Store } from './store';
import { checkUpdates } from './update';
import { GlobalSettings } from '../common/utils';
import { SettingsManager } from '../server/settings';
import { getSiteUrl } from './views/multiplayer/multiplayer';
import { instrumentRuntimeWindow, writeRuntimeDiagnostic } from './runtime-diagnostics';
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

  // Network/live-trace instrumentation remains active before loadURL so the
  // initial SWF/XML/JSON burst is never lost.
  instrumentRuntimeWindow(mainWindow, 'main');

  // The diagnostic panel used to start its 10s readiness timer immediately at
  // BrowserWindow construction. On slow SMB/module startup that timer could
  // expire before the renderer had even reached DOM-ready, producing an
  // unhandled rejection while loadURL was still legitimately in progress.
  // Arm panel readiness from the renderer lifecycle instead. The panel still
  // hooks did-finish-load before it can fire, and the rejection is converted to
  // a settled result immediately so it cannot become an unhandled Promise.
  let diagnosticPanelReady: Promise<{ ok: true } | { ok: false; error: unknown }> | null = null;
  mainWindow.webContents.once('dom-ready', () => {
    writeRuntimeDiagnostic('diagnostic-panel-install-trigger', {
      lifecycle: 'dom-ready',
      url: mainWindow.webContents.getURL()
    });
    diagnosticPanelReady = installWaddleDiagnosticPanel(mainWindow).then(
      () => ({ ok: true as const }),
      error => ({ ok: false as const, error })
    );
  });

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
  if (!diagnosticPanelReady) {
    throw new Error('WADDLE_DIAGNOSTIC_PANEL=FAIL dom_ready_not_observed');
  }
  const diagnosticResult = await diagnosticPanelReady;
  // Use property-existence narrowing instead of boolean-discriminant narrowing.
  // The build intentionally validates with TypeScript 7, whose control-flow
  // analysis around a Promise assigned from an Electron lifecycle callback did
  // not narrow the union reliably at this site.
  if ('error' in diagnosticResult) {
    throw diagnosticResult.error;
  }

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
