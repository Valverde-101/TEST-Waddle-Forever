'use strict';

const fs = require('fs');
const path = require('path');
const { app, BrowserWindow } = require('electron');

const repoRoot = path.resolve(__dirname, '..');
const envPath = path.join(repoRoot, '.env');

function importDotEnv(file) {
  if (!fs.existsSync(file)) return;
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const index = line.indexOf('=');
    if (index < 1) continue;
    const name = line.slice(0, index).trim();
    const value = line.slice(index + 1);
    if (!Object.prototype.hasOwnProperty.call(process.env, name) || !process.env[name]) {
      process.env[name] = value;
    }
  }
}

importDotEnv(envPath);

const defaultPlugin = process.arch === 'ia32'
  ? 'pepflashplayer32_32_0_0_303.dll'
  : 'pepflashplayer64_32_0_0_303.dll';
const pluginPath = path.resolve(
  process.env.WADDLE_PPAPI_FLASH_PATH || path.join(repoRoot, 'assets', 'flash', defaultPlugin)
);
const pluginVersion = (process.env.WADDLE_PPAPI_FLASH_VERSION || '32.0.0.303').trim();
const resultPath = process.env.WADDLE_FLASH_PROBE_RESULT
  ? path.resolve(process.env.WADDLE_FLASH_PROBE_RESULT)
  : path.join(repoRoot, '.work', 'state', 'flash-runtime-probe.json');

function persist(payload) {
  fs.mkdirSync(path.dirname(resultPath), { recursive: true });
  fs.writeFileSync(resultPath, JSON.stringify(payload, null, 2));
}

function fail(reason, extra = {}) {
  const payload = {
    schema: 'waddle-flash-runtime-probe/v1',
    status: 'FAIL',
    reason,
    electron: process.versions.electron || null,
    chromium: process.versions.chrome || null,
    node: process.versions.node || null,
    arch: process.arch,
    platform: process.platform,
    plugin_path: pluginPath,
    plugin_version: pluginVersion,
    ...extra,
  };
  persist(payload);
  console.error(`WADDLE_FLASH_RUNTIME=FAIL reason=${reason} result=${resultPath}`);
  console.error(JSON.stringify(payload));
  app.exit(41);
}

if (process.platform !== 'win32') {
  console.log(`WADDLE_FLASH_RUNTIME=SKIP platform=${process.platform}`);
  app.exit(0);
}

if (!fs.existsSync(pluginPath)) {
  fail('plugin_missing');
}

const stat = fs.statSync(pluginPath);
if (!stat.isFile() || stat.size < 1024 * 1024) {
  fail('plugin_invalid_file', { plugin_size: stat.size });
}

// These Chromium switches must be present before app ready. Testing only that
// the DLL exists is not enough: the renderer must actually expose Flash as a
// PPAPI plugin to the page that embeds the SWF.
app.commandLine.appendSwitch('ppapi-flash-path', pluginPath);
app.commandLine.appendSwitch('ppapi-flash-version', pluginVersion);

const timeout = setTimeout(() => fail('timeout'), 20000);

a ppReady = app.whenReady().then(async () => {
  const configuredPath = app.commandLine.getSwitchValue('ppapi-flash-path');
  const configuredVersion = app.commandLine.getSwitchValue('ppapi-flash-version');
  if (path.resolve(configuredPath) !== pluginPath) {
    fail('switch_path_mismatch', { configured_path: configuredPath });
    return;
  }
  if (configuredVersion !== pluginVersion) {
    fail('switch_version_mismatch', { configured_version: configuredVersion });
    return;
  }

  const win = new BrowserWindow({
    show: false,
    width: 320,
    height: 240,
    webPreferences: {
      plugins: true,
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  const html = '<!doctype html><html><body><object id="flash-probe" type="application/x-shockwave-flash" width="1" height="1"></object></body></html>';
  await win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);

  const renderer = await win.webContents.executeJavaScript(`(() => {
    const plugins = Array.from(navigator.plugins || []).map(p => ({
      name: p.name,
      filename: p.filename,
      description: p.description,
      mimeTypes: Array.from(p).map(m => m.type),
    }));
    const mime = navigator.mimeTypes && navigator.mimeTypes['application/x-shockwave-flash'];
    const element = document.getElementById('flash-probe');
    return {
      userAgent: navigator.userAgent,
      plugins,
      mimePresent: !!mime,
      mimeEnabledPlugin: !!(mime && mime.enabledPlugin),
      mimePluginName: mime && mime.enabledPlugin ? mime.enabledPlugin.name : null,
      objectType: element ? element.type : null,
    };
  })()`, true);

  const flashPlugins = renderer.plugins.filter(plugin => {
    const text = `${plugin.name} ${plugin.filename} ${plugin.description} ${plugin.mimeTypes.join(' ')}`;
    return /flash|shockwave/i.test(text) || plugin.mimeTypes.includes('application/x-shockwave-flash');
  });
  const flashAvailable = renderer.mimeEnabledPlugin || flashPlugins.length > 0;

  const payload = {
    schema: 'waddle-flash-runtime-probe/v1',
    status: flashAvailable ? 'PASS' : 'FAIL',
    reason: flashAvailable ? null : 'renderer_flash_plugin_absent',
    electron: process.versions.electron || null,
    chromium: process.versions.chrome || null,
    node: process.versions.node || null,
    arch: process.arch,
    platform: process.platform,
    plugin_path: pluginPath,
    plugin_size: stat.size,
    plugin_version: pluginVersion,
    switch_path: configuredPath,
    switch_version: configuredVersion,
    renderer,
    flash_plugins: flashPlugins,
  };

  persist(payload);
  clearTimeout(timeout);
  win.destroy();

  if (!flashAvailable) {
    console.error(`WADDLE_FLASH_RUNTIME=FAIL reason=renderer_flash_plugin_absent result=${resultPath}`);
    console.error(JSON.stringify(payload));
    app.exit(42);
    return;
  }

  console.log(`WADDLE_FLASH_RUNTIME=PASS electron=${payload.electron} chromium=${payload.chromium} plugin=${pluginPath} version=${pluginVersion} mime=application/x-shockwave-flash result=${resultPath}`);
  console.log(JSON.stringify(payload));
  app.exit(0);
}).catch(error => {
  clearTimeout(timeout);
  fail('probe_exception', { error: error && error.stack ? error.stack : String(error) });
});

void a ppReady;
