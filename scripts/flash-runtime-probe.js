'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const { app, BrowserWindow } = require('electron');

// Waddle has two intentionally separate roots on Windows:
// - sourceRoot: mutable user/content root (media, settings, .env, evidence)
// - runtimeAppRoot: immutable deployed executable app (compiled + runtime deps)
// Keeping cwd at sourceRoot preserves the real desktop launch semantics while
// allowing CI to prove that executable JS is loaded from the external runtime.
const inferredRoot = path.resolve(__dirname, '..');
const sourceRoot = path.resolve(process.env.WADDLE_SOURCE_ROOT || inferredRoot);
const runtimeAppRoot = path.resolve(process.env.WADDLE_RUNTIME_APP_ROOT || sourceRoot);
process.chdir(sourceRoot);
process.env.NODE_ENV = 'dev';

const envPath = path.join(sourceRoot, '.env');
const settingsPath = path.join(sourceRoot, 'settings.json');
const resultPath = process.env.WADDLE_FLASH_PROBE_RESULT
  ? path.resolve(process.env.WADDLE_FLASH_PROBE_RESULT)
  : path.join(sourceRoot, '.work', 'state', 'flash-runtime-probe.json');

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
  process.env.WADDLE_PPAPI_FLASH_PATH || path.join(sourceRoot, 'assets', 'flash', defaultPlugin)
);
const pluginVersion = (process.env.WADDLE_PPAPI_FLASH_VERSION || '32.0.0.303').trim();
const compiledRoot = path.join(runtimeAppRoot, 'compiled');
const runtimeModulesRoot = path.join(runtimeAppRoot, 'node_modules');
const settingsBackup = fs.existsSync(settingsPath) ? fs.readFileSync(settingsPath) : null;

let server = null;
let finished = false;

function persist(payload) {
  fs.mkdirSync(path.dirname(resultPath), { recursive: true });
  fs.writeFileSync(resultPath, JSON.stringify(payload, null, 2));
}

function restoreSettings() {
  try {
    if (settingsBackup === null) {
      fs.rmSync(settingsPath, { force: true });
    } else {
      fs.writeFileSync(settingsPath, settingsBackup);
    }
  } catch (_) {}
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
  restoreSettings();
  persist(payload);
  const marker = payload.status === 'PASS' ? 'PASS' : 'FAIL';
  const reason = payload.reason ? ` reason=${payload.reason}` : '';
  console.log(`WADDLE_FLASH_RUNTIME=${marker}${reason} result=${resultPath}`);
  console.log(JSON.stringify(payload));
  setImmediate(() => app.exit(code));
}

function basePayload(status, reason, extra = {}) {
  return {
    schema: 'waddle-flash-runtime-probe/v4',
    status,
    reason,
    electron: process.versions.electron || null,
    chromium: process.versions.chrome || null,
    node: process.versions.node || null,
    arch: process.arch,
    platform: process.platform,
    source_root: sourceRoot,
    runtime_app_root: runtimeAppRoot,
    runtime_compiled_root: compiledRoot,
    runtime_node_modules: runtimeModulesRoot,
    cwd: process.cwd(),
    plugin_path: pluginPath,
    plugin_version: pluginVersion,
    ...extra,
  };
}

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(Buffer.from(chunk)));
      response.on('end', () => resolve({
        statusCode: response.statusCode || 0,
        headers: response.headers,
        body: Buffer.concat(chunks),
      }));
    });
    req.on('error', reject);
    req.setTimeout(10000, () => req.destroy(new Error(`HTTP timeout: ${url}`)));
  });
}

if (process.platform !== 'win32') {
  finish(0, basePayload('PASS', 'not_windows'));
}
if (!fs.existsSync(pluginPath)) {
  finish(41, basePayload('FAIL', 'plugin_missing'));
}
if (!fs.existsSync(path.join(compiledRoot, 'server', 'file-server', 'index.js'))) {
  finish(41, basePayload('FAIL', 'compiled_fileserver_missing'));
}
if (!fs.existsSync(runtimeModulesRoot)) {
  finish(41, basePayload('FAIL', 'runtime_node_modules_missing'));
}
if (!fs.existsSync(path.join(sourceRoot, 'media', 'default'))) {
  finish(41, basePayload('FAIL', 'source_media_default_missing'));
}

const pluginStat = fs.statSync(pluginPath);
if (!pluginStat.isFile() || pluginStat.size < 1024 * 1024) {
  finish(41, basePayload('FAIL', 'plugin_invalid_file', { plugin_size: pluginStat.size }));
}

// Pepper Flash must be configured before Electron is ready. The rest of this
// probe deliberately exercises Waddle's real FileServer and real timeline page,
// not a synthetic HTML fixture, so a PASS means the same / -> /boots.swf chain
// used by the desktop client can actually instantiate Flash.
app.commandLine.appendSwitch('ppapi-flash-path', pluginPath);
app.commandLine.appendSwitch('ppapi-flash-version', pluginVersion);

const timeout = setTimeout(() => {
  finish(43, basePayload('FAIL', 'timeout'));
}, 30000);

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

  // Force a deterministic default timeline while preserving any existing local
  // settings bytes and restoring them before this process exits.
  fs.writeFileSync(settingsPath, JSON.stringify({
    version: '2010-10-25',
    fps30: false,
    minified_website: false,
    faq_warning: true,
    clothing: false,
    answered_packages: 'probe',
  }));

  // Load the server-side runtime dependency explicitly from the deployed app.
  // This prevents the probe script's own source-tree location from accidentally
  // resolving express through the mutable build node_modules junction.
  const express = require(path.join(runtimeModulesRoot, 'express'));
  const settingsModule = require(path.join(compiledRoot, 'server', 'settings.js'));
  const settingsManager = settingsModule.default || settingsModule;
  const { GameData } = require(path.join(compiledRoot, 'server', 'timelines', 'game-data.js'));
  const { FileServer } = require(path.join(compiledRoot, 'server', 'file-server', 'index.js'));

  const gameData = new GameData(settingsManager);
  const fileServer = new FileServer(gameData, settingsManager);
  const expressApp = express();
  const observedResponses = [];
  expressApp.use((req, res, next) => {
    const started = Date.now();
    res.on('finish', () => {
      if (req.path === '/' || req.path === '/boots.swf') {
        observedResponses.push({
          path: req.path,
          status: res.statusCode,
          contentType: String(res.getHeader('content-type') || ''),
          durationMs: Date.now() - started,
        });
      }
    });
    next();
  });
  expressApp.use(fileServer.getExpressRouter());

  server = http.createServer(expressApp);
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
  const baseUrl = `http://127.0.0.1:${port}`;

  const rootResponse = await fetchBuffer(`${baseUrl}/`);
  const bootsResponse = await fetchBuffer(`${baseUrl}/boots.swf`);
  const rootHtml = rootResponse.body.toString('utf8');
  const swfSignature = bootsResponse.body.slice(0, 3).toString('ascii');
  const bootsContentType = String(bootsResponse.headers['content-type'] || '');
  const htmlHasBootsObject = /<object[^>]+application\/x-shockwave-flash[^>]+data=["']\/boots\.swf["']/i.test(rootHtml)
    || /<object[^>]+data=["']\/boots\.swf["'][^>]+application\/x-shockwave-flash/i.test(rootHtml);

  if (rootResponse.statusCode !== 200) {
    finish(42, basePayload('FAIL', 'production_root_http_status', { status: rootResponse.statusCode }));
    return;
  }
  if (bootsResponse.statusCode !== 200) {
    finish(42, basePayload('FAIL', 'production_boots_http_status', { status: bootsResponse.statusCode }));
    return;
  }
  if (!/application\/x-shockwave-flash/i.test(bootsContentType)) {
    finish(42, basePayload('FAIL', 'production_boots_mime_invalid', { content_type: bootsContentType }));
    return;
  }
  if (!['FWS', 'CWS', 'ZWS'].includes(swfSignature)) {
    finish(42, basePayload('FAIL', 'production_boots_invalid_swf', {
      swf_signature: swfSignature,
      boots_size: bootsResponse.body.length,
    }));
    return;
  }
  if (!htmlHasBootsObject) {
    finish(42, basePayload('FAIL', 'production_html_boots_object_missing'));
    return;
  }

  const win = new BrowserWindow({
    show: false,
    width: 1280,
    height: 720,
    webPreferences: {
      plugins: true,
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  let loadFailure = null;
  win.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedURL, isMainFrame) => {
    if (isMainFrame) {
      loadFailure = { errorCode, errorDescription, validatedURL };
    }
  });

  await win.loadURL(`${baseUrl}/`);
  await new Promise(resolve => setTimeout(resolve, 2000));

  const renderer = await win.webContents.executeJavaScript(`(() => {
    const plugins = Array.from(navigator.plugins || []).map(p => ({
      name: p.name,
      filename: p.filename,
      description: p.description,
      mimeTypes: Array.from(p).map(m => m.type),
    }));
    const mime = navigator.mimeTypes && navigator.mimeTypes['application/x-shockwave-flash'];
    const object = document.getElementById('game') || document.querySelector('object[type="application/x-shockwave-flash"]');
    const fallback = document.getElementById('noflash') || (object && object.querySelector ? object.querySelector('img, a, div') : null);
    const fallbackStyle = fallback ? getComputedStyle(fallback) : null;
    const fallbackRects = fallback ? fallback.getClientRects().length : -1;
    const methods = ['PercentLoaded', 'GetVariable', 'SetVariable'].filter(name => object && typeof object[name] === 'function');
    return {
      href: location.href,
      title: document.title,
      readyState: document.readyState,
      userAgent: navigator.userAgent,
      plugins,
      mimePresent: !!mime,
      mimeEnabledPlugin: !!(mime && mime.enabledPlugin),
      mimePluginName: mime && mime.enabledPlugin ? mime.enabledPlugin.name : null,
      objectPresent: !!object,
      objectType: object ? object.type : null,
      objectData: object ? object.data : null,
      fallbackPresent: !!fallback,
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
  const fallbackVisible = renderer.fallbackPresent
    && renderer.fallbackRects > 0
    && renderer.fallbackDisplay !== 'none'
    && renderer.fallbackVisibility !== 'hidden';
  const flashAvailable = renderer.mimeEnabledPlugin && flashPlugins.length > 0;
  const scriptable = renderer.scriptableMethods.length > 0;
  const productionPass = !loadFailure
    && flashAvailable
    && renderer.objectPresent
    && !fallbackVisible
    && scriptable;

  const payload = basePayload(
    productionPass ? 'PASS' : 'FAIL',
    productionPass ? null : 'production_page_flash_not_instantiated',
    {
      plugin_size: pluginStat.size,
      switch_path: configuredPath,
      switch_version: configuredVersion,
      production_url: `${baseUrl}/`,
      root_status: rootResponse.statusCode,
      root_content_type: String(rootResponse.headers['content-type'] || ''),
      root_size: rootResponse.body.length,
      html_has_boots_object: htmlHasBootsObject,
      boots_status: bootsResponse.statusCode,
      boots_content_type: bootsContentType,
      boots_size: bootsResponse.body.length,
      swf_signature: swfSignature,
      observed_responses: observedResponses,
      renderer,
      flash_plugins: flashPlugins,
      fallback_visible: fallbackVisible,
      scriptable_flash_object: scriptable,
      load_failure: loadFailure,
      production_instantiated: productionPass,
    }
  );

  clearTimeout(timeout);
  win.destroy();
  finish(productionPass ? 0 : 42, payload);
}).catch(error => {
  clearTimeout(timeout);
  finish(44, basePayload('FAIL', 'probe_exception', {
    error: error && error.stack ? error.stack : String(error),
  }));
});

void appReady;
