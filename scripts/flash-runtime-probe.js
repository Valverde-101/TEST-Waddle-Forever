'use strict';

const fs = require('fs');
const http = require('http');
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
const bootsPath = path.join(repoRoot, 'media', 'default', 'tool', 'boots.swf');
const resultPath = process.env.WADDLE_FLASH_PROBE_RESULT
  ? path.resolve(process.env.WADDLE_FLASH_PROBE_RESULT)
  : path.join(repoRoot, '.work', 'state', 'flash-runtime-probe.json');

let server = null;
let finished = false;

function persist(payload) {
  fs.mkdirSync(path.dirname(resultPath), { recursive: true });
  fs.writeFileSync(resultPath, JSON.stringify(payload, null, 2));
}

function stopServer() {
  if (server) {
    try { server.close(); } catch (_) {}
    server = null;
  }
}

function finish(code, payload) {
  if (finished) return;
  finished = true;
  stopServer();
  persist(payload);
  const marker = payload.status === 'PASS' ? 'PASS' : 'FAIL';
  const reason = payload.reason ? ` reason=${payload.reason}` : '';
  console.log(`WADDLE_FLASH_RUNTIME=${marker}${reason} result=${resultPath}`);
  console.log(JSON.stringify(payload));
  setImmediate(() => app.exit(code));
}

function basePayload(status, reason, extra = {}) {
  return {
    schema: 'waddle-flash-runtime-probe/v2',
    status,
    reason,
    electron: process.versions.electron || null,
    chromium: process.versions.chrome || null,
    node: process.versions.node || null,
    arch: process.arch,
    platform: process.platform,
    plugin_path: pluginPath,
    plugin_version: pluginVersion,
    boots_path: bootsPath,
    ...extra,
  };
}

if (process.platform !== 'win32') {
  finish(0, basePayload('PASS', 'not_windows'));
}

if (!fs.existsSync(pluginPath)) {
  finish(41, basePayload('FAIL', 'plugin_missing'));
}
if (!fs.existsSync(bootsPath)) {
  finish(41, basePayload('FAIL', 'boots_swf_missing'));
}

const pluginStat = fs.statSync(pluginPath);
const boots = fs.readFileSync(bootsPath);
const swfSignature = boots.slice(0, 3).toString('ascii');
if (!pluginStat.isFile() || pluginStat.size < 1024 * 1024) {
  finish(41, basePayload('FAIL', 'plugin_invalid_file', { plugin_size: pluginStat.size }));
}
if (!['FWS', 'CWS', 'ZWS'].includes(swfSignature)) {
  finish(41, basePayload('FAIL', 'boots_invalid_swf', { swf_signature: swfSignature, boots_size: boots.length }));
}

// Chromium must receive the PPAPI switches before ready. This test then goes
// further than navigator.plugins: it serves Waddle's real boots.swf over HTTP,
// embeds it exactly as the production page does, and verifies that the renderer
// requests the SWF while the HTML fallback remains hidden.
app.commandLine.appendSwitch('ppapi-flash-path', pluginPath);
app.commandLine.appendSwitch('ppapi-flash-version', pluginVersion);

const timeout = setTimeout(() => {
  finish(43, basePayload('FAIL', 'timeout'));
}, 25000);

const appReady = app.whenReady().then(async () => {
  const configuredPath = app.commandLine.getSwitchValue('ppapi-flash-path');
  const configuredVersion = app.commandLine.getSwitchValue('ppapi-flash-version');
  if (path.resolve(configuredPath) !== pluginPath) {
    finish(41, basePayload('FAIL', 'switch_path_mismatch', { configured_path: configuredPath }));
    return;
  }
  if (configuredVersion !== pluginVersion) {
    finish(41, basePayload('FAIL', 'switch_version_mismatch', { configured_version: configuredVersion }));
    return;
  }

  let swfRequests = 0;
  let htmlRequests = 0;
  server = http.createServer((req, res) => {
    if (req.url === '/boots.swf') {
      swfRequests += 1;
      res.writeHead(200, {
        'Content-Type': 'application/x-shockwave-flash',
        'Content-Length': boots.length,
        'Cache-Control': 'no-store',
      });
      res.end(boots);
      return;
    }

    htmlRequests += 1;
    const html = '<!doctype html><html><body style="margin:0"><object id="flash-probe" type="application/x-shockwave-flash" data="/boots.swf" width="320" height="240"><div id="fallback">FLASH_FALLBACK_VISIBLE</div></object></body></html>';
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    res.end(html);
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  if (!port) {
    finish(41, basePayload('FAIL', 'probe_server_port_missing'));
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

  await win.loadURL(`http://127.0.0.1:${port}/`);
  await new Promise(resolve => setTimeout(resolve, 1500));

  const renderer = await win.webContents.executeJavaScript(`(() => {
    const plugins = Array.from(navigator.plugins || []).map(p => ({
      name: p.name,
      filename: p.filename,
      description: p.description,
      mimeTypes: Array.from(p).map(m => m.type),
    }));
    const mime = navigator.mimeTypes && navigator.mimeTypes['application/x-shockwave-flash'];
    const object = document.getElementById('flash-probe');
    const fallback = document.getElementById('fallback');
    const fallbackStyle = fallback ? getComputedStyle(fallback) : null;
    const fallbackRects = fallback ? fallback.getClientRects().length : -1;
    const methods = ['PercentLoaded', 'GetVariable', 'SetVariable'].filter(name => object && typeof object[name] === 'function');
    return {
      userAgent: navigator.userAgent,
      plugins,
      mimePresent: !!mime,
      mimeEnabledPlugin: !!(mime && mime.enabledPlugin),
      mimePluginName: mime && mime.enabledPlugin ? mime.enabledPlugin.name : null,
      objectType: object ? object.type : null,
      objectData: object ? object.data : null,
      fallbackRects,
      fallbackDisplay: fallbackStyle ? fallbackStyle.display : null,
      fallbackVisibility: fallbackStyle ? fallbackStyle.visibility : null,
      scriptableMethods: methods,
    };
  })()`, true);

  const flashPlugins = renderer.plugins.filter(plugin => {
    const text = `${plugin.name} ${plugin.filename} ${plugin.description} ${plugin.mimeTypes.join(' ')}`;
    return /flash|shockwave/i.test(text) || plugin.mimeTypes.includes('application/x-shockwave-flash');
  });
  const fallbackVisible = renderer.fallbackRects > 0 && renderer.fallbackDisplay !== 'none' && renderer.fallbackVisibility !== 'hidden';
  const flashAvailable = renderer.mimeEnabledPlugin && flashPlugins.length > 0;
  const swfInstantiated = flashAvailable && swfRequests > 0 && !fallbackVisible;

  const payload = basePayload(
    swfInstantiated ? 'PASS' : 'FAIL',
    swfInstantiated ? null : 'swf_not_instantiated',
    {
      plugin_size: pluginStat.size,
      boots_size: boots.length,
      swf_signature: swfSignature,
      switch_path: configuredPath,
      switch_version: configuredVersion,
      html_requests: htmlRequests,
      swf_requests: swfRequests,
      renderer,
      flash_plugins: flashPlugins,
      fallback_visible: fallbackVisible,
      swf_instantiated: swfInstantiated,
    }
  );

  clearTimeout(timeout);
  win.destroy();
  finish(swfInstantiated ? 0 : 42, payload);
}).catch(error => {
  clearTimeout(timeout);
  finish(44, basePayload('FAIL', 'probe_exception', {
    error: error && error.stack ? error.stack : String(error),
  }));
});

void appReady;
