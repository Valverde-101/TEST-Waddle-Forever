import fs from 'fs';
import os from 'os';
import path from 'path';
import type { BrowserWindow, Session } from 'electron';
import {
  publishWaddleLiveTrace,
  subscribeWaddleLiveTrace,
  WaddleLiveTraceEvent
} from '@common/live-trace';

const runtimeLogDirectory = path.join(process.cwd(), '.work', 'logs', 'runtime');
const explicitDiagnosticPath = process.env.WADDLE_RUNTIME_DIAGNOSTIC_LOG?.trim();
const runtimeLeaseRoot = path.join(process.cwd(), '.work', 'state', 'runtime-leases');
const slowResourceThresholdMs = Math.max(250, Number(process.env.WADDLE_SLOW_RESOURCE_MS || 2000) || 2000);
const healthIntervalMs = Math.max(15000, Number(process.env.WADDLE_RUNTIME_HEALTH_MS || 60000) || 60000);
const liveTraceHistoryLimit = Math.max(200, Math.min(5000, Number(process.env.WADDLE_LIVE_TRACE_HISTORY || 1500) || 1500));
const liveTraceReplayLimit = Math.max(50, Math.min(1000, Number(process.env.WADDLE_LIVE_TRACE_REPLAY || 300) || 300));

const getLatestLauncherStderr = (): string | undefined => {
  try {
    if (!fs.existsSync(runtimeLogDirectory)) {
      return undefined;
    }

    const candidates = fs.readdirSync(runtimeLogDirectory)
      .filter(name => /^client-(?:.+-)?\d{8}-\d{6}\.stderr\.log$/i.test(name))
      .map(name => {
        const fullPath = path.join(runtimeLogDirectory, name);
        return { path: fullPath, mtime: fs.statSync(fullPath).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime);

    const latest = candidates[0];
    if (!latest) {
      return undefined;
    }

    if (Date.now() - latest.mtime > 120_000) {
      return undefined;
    }

    return latest.path;
  } catch {
    return undefined;
  }
};

const diagnosticPath = explicitDiagnosticPath
  || getLatestLauncherStderr()
  || path.join(runtimeLogDirectory, 'application-errors.log');

const serializeError = (value: unknown) => {
  if (value instanceof Error) {
    return {
      name: value.name,
      message: value.message,
      stack: value.stack ?? null
    };
  }

  return { value: String(value) };
};

const trimText = (value: unknown, maxLength = 4096) => {
  const text = String(value ?? '');
  return text.length <= maxLength ? text : `${text.slice(0, maxLength)}...[truncated]`;
};

const sanitizeUrl = (value: string) => {
  try {
    const parsed = new URL(value);
    parsed.username = '';
    parsed.password = '';
    const sensitive = /pass|password|token|auth|session|secret|key/i;
    for (const key of Array.from(parsed.searchParams.keys())) {
      if (sensitive.test(key)) {
        parsed.searchParams.set(key, '[redacted]');
      }
    }
    return trimText(parsed.toString(), 4096);
  } catch {
    return trimText(value, 4096);
  }
};

const appendRuntimeDiagnostic = (
  event: string,
  detail: Record<string, unknown>,
  strict: boolean
) => {
  try {
    fs.mkdirSync(path.dirname(diagnosticPath), { recursive: true });
    fs.appendFileSync(diagnosticPath, `${JSON.stringify({
      schema: 'waddle-runtime-event/v1',
      utc: new Date().toISOString(),
      event,
      pid: process.pid,
      ...detail
    })}\n`, 'utf8');
  } catch (error) {
    if (strict) {
      const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
      throw new Error(`WADDLE_RUNTIME_DIAGNOSTIC_WRITE=FAIL path=${diagnosticPath} error=${message}`);
    }
  }
};

export const writeRuntimeDiagnostic = (event: string, detail: Record<string, unknown> = {}) => {
  appendRuntimeDiagnostic(event, detail, false);
};

type RuntimeLease = {
  id: string;
  directory: string;
  ownerPath: string;
  heartbeat: string;
  timer: NodeJS.Timeout;
};

let runtimeLease: RuntimeLease | undefined;

const releaseRuntimeLease = () => {
  if (!runtimeLease) {
    return;
  }

  try {
    clearInterval(runtimeLease.timer);
    for (const file of [runtimeLease.heartbeat, runtimeLease.ownerPath]) {
      try {
        if (fs.existsSync(file)) {
          fs.unlinkSync(file);
        }
      } catch {
        // The stale-lease cleaner handles any file that SMB could not remove
        // during process shutdown.
      }
    }
    try {
      fs.rmdirSync(runtimeLease.directory);
    } catch {
      // Same-host dead-PID cleanup removes this immediately on the next write;
      // remote clients fall back to heartbeat expiry.
    }
  } finally {
    runtimeLease = undefined;
  }
};

const acquireRuntimeLease = () => {
  if (runtimeLease) {
    return runtimeLease;
  }

  const machine = os.hostname();
  const token = Math.random().toString(16).slice(2);
  const id = `${machine}-${process.pid}-${Date.now()}-${token}`.replace(/[^a-zA-Z0-9_.-]/g, '_');
  const directory = path.join(runtimeLeaseRoot, id);
  const ownerPath = path.join(directory, 'owner.json');
  const heartbeat = path.join(directory, 'heartbeat');

  fs.mkdirSync(runtimeLeaseRoot, { recursive: true });
  fs.mkdirSync(directory, { recursive: false });

  const owner = {
    schema: 'waddle-runtime-lease/v1',
    id,
    machine,
    pid: process.pid,
    cwd: process.cwd(),
    electron: process.versions.electron ?? null,
    started_utc: new Date().toISOString()
  };
  fs.writeFileSync(ownerPath, JSON.stringify(owner), 'utf8');
  fs.writeFileSync(heartbeat, new Date().toISOString(), 'utf8');

  let consecutiveFailures = 0;
  const timer = setInterval(() => {
    try {
      fs.writeFileSync(heartbeat, new Date().toISOString(), 'utf8');
      consecutiveFailures = 0;
    } catch (error) {
      consecutiveFailures += 1;
      appendRuntimeDiagnostic('runtime-lease-heartbeat-failed', {
        lease: directory,
        consecutiveFailures,
        error: serializeError(error)
      }, false);
      if (consecutiveFailures >= 3) {
        process.exit(1);
      }
    }
  }, 5000);
  timer.unref();

  runtimeLease = { id, directory, ownerPath, heartbeat, timer };
  process.once('exit', releaseRuntimeLease);

  appendRuntimeDiagnostic('runtime-lease-acquired', {
    lease: directory,
    machine,
    heartbeatIntervalMs: 5000
  }, Boolean(explicitDiagnosticPath));

  return runtimeLease;
};

let diagnosticsInstalled = false;

export const installRuntimeDiagnostics = () => {
  if (diagnosticsInstalled) {
    return diagnosticPath;
  }

  appendRuntimeDiagnostic('main-process-boot', {
    electron: process.versions.electron ?? null,
    chromium: process.versions.chrome ?? null,
    node: process.versions.node,
    cwd: process.cwd(),
    explicitPath: Boolean(explicitDiagnosticPath),
    slowResourceThresholdMs,
    healthIntervalMs,
    liveTraceHistoryLimit,
    liveTraceReplayLimit
  }, Boolean(explicitDiagnosticPath));

  try {
    acquireRuntimeLease();
  } catch (error) {
    const detail = serializeError(error);
    appendRuntimeDiagnostic('runtime-lease-acquire-failed', detail, false);
    const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    throw new Error(`WADDLE_RUNTIME_LEASE=FAIL root=${runtimeLeaseRoot} error=${message}`);
  }

  process.on('unhandledRejection', reason => {
    writeRuntimeDiagnostic('unhandled-rejection', serializeError(reason));
  });

  process.on('uncaughtException', error => {
    writeRuntimeDiagnostic('uncaught-exception', serializeError(error));
    process.exit(1);
  });

  diagnosticsInstalled = true;
  return diagnosticPath;
};

export const runtimeDiagnosticPath = installRuntimeDiagnostics();

const instrumentedSessions = new WeakSet<Session>();
const instrumentedWindows = new WeakSet<BrowserWindow>();
const liveTraceTargets = new Set<BrowserWindow>();
const liveTraceHistory: WaddleLiveTraceEvent[] = [];

const serializeForRenderer = (value: unknown) => JSON.stringify(value).replace(/</g, '\\u003c');

const bootstrapLiveTraceConsole = (window: BrowserWindow) => {
  if (window.isDestroyed() || window.webContents.isDestroyed()) {
    return;
  }

  const replay = liveTraceHistory.slice(-liveTraceReplayLimit);
  const script = `(() => {
    const w = window;
    w.__WADDLE_LIVE_TRACE__ = [];
    w.__WADDLE_EMIT_TRACE__ = (event) => {
      const history = w.__WADDLE_LIVE_TRACE__;
      history.push(event);
      if (history.length > ${liveTraceHistoryLimit}) history.splice(0, history.length - ${liveTraceHistoryLimit});
      const category = String(event.category || 'TRACE').toUpperCase();
      const phase = String(event.phase || 'state').toUpperCase();
      const parts = [];
      if (event.requestId !== undefined && event.requestId !== null) parts.push('req=' + event.requestId);
      if (event.action) parts.push('action=' + event.action);
      if (event.method) parts.push('method=' + event.method);
      if (event.statusCode !== undefined && event.statusCode !== null) parts.push('status=' + event.statusCode);
      if (event.status) parts.push('result=' + event.status);
      if (event.durationMs !== undefined && event.durationMs !== null) parts.push('time=' + event.durationMs + 'ms');
      if (event.fromCache) parts.push('cache=yes');
      if (event.resolver) parts.push('resolver=' + event.resolver);
      if (event.target) parts.push('target=' + event.target);
      if (event.error) parts.push('error=' + event.error);
      if (event.url) parts.push(event.url);
      const prefix = '[WADDLE-LIVE][' + category + '][' + phase + '] #' + event.sequence;
      if (phase === 'ERROR') console.error(prefix, parts.join(' '), event);
      else console.log(prefix, parts.join(' '), event);
    };
    console.log('[WADDLE-LIVE][READY] Real-time SWF/HTTP/XT/XML tracing enabled. Filter the Console with WADDLE-LIVE. History: window.__WADDLE_LIVE_TRACE__');
    const replay = ${serializeForRenderer(replay)};
    for (const event of replay) w.__WADDLE_EMIT_TRACE__({ ...event, replayed: true });
  })()`;

  void window.webContents.executeJavaScript(script, true).then(() => {
    writeRuntimeDiagnostic('live-trace-console-ready', {
      url: sanitizeUrl(window.webContents.getURL()),
      replayed: replay.length
    });
  }).catch(error => {
    writeRuntimeDiagnostic('live-trace-console-bootstrap-failed', {
      error: serializeError(error),
      url: sanitizeUrl(window.webContents.getURL())
    });
  });
};

const emitLiveTraceToRenderer = (window: BrowserWindow, event: WaddleLiveTraceEvent) => {
  if (window.isDestroyed() || window.webContents.isDestroyed()) {
    liveTraceTargets.delete(window);
    return;
  }

  const script = `(() => {
    if (typeof window.__WADDLE_EMIT_TRACE__ === 'function') {
      window.__WADDLE_EMIT_TRACE__(${serializeForRenderer(event)});
    }
  })()`;
  void window.webContents.executeJavaScript(script, true).catch(() => {
    // Initial requests can happen before the renderer context exists. They are
    // kept in the main-process ring buffer and replayed after did-finish-load.
  });
};

subscribeWaddleLiveTrace(event => {
  liveTraceHistory.push(event);
  if (liveTraceHistory.length > liveTraceHistoryLimit) {
    liveTraceHistory.splice(0, liveTraceHistory.length - liveTraceHistoryLimit);
  }

  writeRuntimeDiagnostic('live-trace', { trace: event });
  for (const target of liveTraceTargets) {
    emitLiveTraceToRenderer(target, event);
  }
});

const getResourceKind = (url: string, resourceType: string) => {
  if (/\.swf(?:[?#]|$)/i.test(url)) return 'SWF';
  if (/\.xml(?:[?#]|$)/i.test(url)) return 'XML';
  if (/\.json(?:[?#]|$)/i.test(url)) return 'JSON';
  if (/\.js(?:[?#]|$)/i.test(url)) return 'JS';
  if (/\.css(?:[?#]|$)/i.test(url)) return 'CSS';
  if (/websocket/i.test(resourceType)) return 'WS';
  if (/xhr/i.test(resourceType)) return 'XHR';
  if (/object/i.test(resourceType)) return 'OBJECT';
  return resourceType ? resourceType.toUpperCase() : 'RESOURCE';
};

const getResourceAction = (url: string) => {
  try {
    const parsed = new URL(url);
    for (const key of ['action', 'cmd', 'command', 'opcode', 'handler']) {
      const value = parsed.searchParams.get(key);
      if (value) return trimText(value, 128);
    }
    const parts = parsed.pathname.split('/').filter(Boolean);
    return trimText(parts[parts.length - 1] || parsed.pathname || '/', 160);
  } catch {
    const clean = url.split('?')[0];
    const parts = clean.split('/').filter(Boolean);
    return trimText(parts[parts.length - 1] || clean, 160);
  }
};

const isInterestingResource = (url: string, resourceType: string) => {
  if (/\.(?:swf|xml|json|js|css)(?:[?#]|$)/i.test(url)) {
    return true;
  }
  if (/\/(?:play|login|world|game|media|assets?|files?|api)(?:\/|\?|$)/i.test(url)) {
    return true;
  }
  return /^(?:xhr|object|script|webSocket)$/i.test(resourceType);
};

type RequestTiming = {
  startedAt: number;
  interesting: boolean;
  resourceType: string;
  url: string;
  action: string;
  category: string;
};

const instrumentSession = (session: Session) => {
  if (instrumentedSessions.has(session)) {
    return;
  }
  instrumentedSessions.add(session);

  const requests = new Map<number, RequestTiming>();
  let requestTimingEvictions = 0;

  session.webRequest.onBeforeRequest((details, callback) => {
    const resourceType = String(details.resourceType || 'unknown');
    const url = sanitizeUrl(details.url);
    const interesting = isInterestingResource(url, resourceType);
    const category = getResourceKind(url, resourceType);
    const action = getResourceAction(url);

    requests.set(details.id, {
      startedAt: Date.now(),
      interesting,
      resourceType,
      url,
      action,
      category
    });

    if (requests.size > 20000) {
      const oldest = requests.keys().next();
      if (!oldest.done) requests.delete(oldest.value);
      requestTimingEvictions += 1;
      if (requestTimingEvictions === 1 || requestTimingEvictions % 1000 === 0) {
        writeRuntimeDiagnostic('resource-timing-eviction', {
          reason: 'request_map_limit',
          evictions: requestTimingEvictions,
          retained: requests.size
        });
      }
    }

    if (interesting) {
      publishWaddleLiveTrace({
        category,
        phase: 'request',
        source: 'electron-webrequest',
        action,
        requestId: details.id,
        method: details.method,
        resourceType,
        url,
        direction: 'out'
      });
    }

    callback({ cancel: false });
  });

  session.webRequest.onCompleted(details => {
    const request = requests.get(details.id);
    requests.delete(details.id);
    const durationMs = request === undefined ? null : Math.max(0, Date.now() - request.startedAt);
    const resourceType = request?.resourceType || String(details.resourceType || 'unknown');
    const url = request?.url || sanitizeUrl(details.url);
    const action = request?.action || getResourceAction(url);
    const category = request?.category || getResourceKind(url, resourceType);
    const statusCode = Number(details.statusCode || 0);
    const slow = durationMs !== null && durationMs >= slowResourceThresholdMs;
    const failedStatus = statusCode >= 400;
    const interesting = request?.interesting ?? isInterestingResource(url, resourceType);

    if (interesting || slow || failedStatus) {
      writeRuntimeDiagnostic('resource-response', {
        requestId: details.id,
        method: details.method,
        resourceType,
        url,
        statusCode,
        fromCache: Boolean(details.fromCache),
        durationMs,
        slow,
        failedStatus
      });

      publishWaddleLiveTrace({
        category,
        phase: failedStatus ? 'error' : 'response',
        source: 'electron-webrequest',
        action,
        requestId: details.id,
        method: details.method,
        resourceType,
        url,
        statusCode,
        status: failedStatus ? 'http-error' : 'ok',
        fromCache: Boolean(details.fromCache),
        durationMs,
        slow,
        direction: 'in'
      });
    }

    if (slow) {
      writeRuntimeDiagnostic('resource-slow', {
        requestId: details.id,
        resourceType,
        url,
        statusCode,
        durationMs,
        thresholdMs: slowResourceThresholdMs
      });
    }
  });

  session.webRequest.onErrorOccurred(details => {
    const request = requests.get(details.id);
    requests.delete(details.id);
    const url = request?.url || sanitizeUrl(details.url);
    const resourceType = request?.resourceType || String(details.resourceType || 'unknown');
    const action = request?.action || getResourceAction(url);
    const category = request?.category || getResourceKind(url, resourceType);
    const durationMs = request === undefined ? null : Math.max(0, Date.now() - request.startedAt);
    const error = trimText(details.error, 2048);
    const aborted = /ERR_ABORTED/i.test(error);

    writeRuntimeDiagnostic('resource-load-failed', {
      requestId: details.id,
      method: details.method,
      resourceType,
      url,
      error,
      durationMs,
      aborted
    });

    publishWaddleLiveTrace({
      category,
      phase: aborted ? 'state' : 'error',
      source: 'electron-webrequest',
      action,
      requestId: details.id,
      method: details.method,
      resourceType,
      url,
      status: aborted ? 'aborted' : 'network-error',
      error,
      durationMs,
      direction: 'in',
      benign: aborted
    });
  });

  writeRuntimeDiagnostic('session-network-diagnostics-ready', {
    slowResourceThresholdMs,
    liveTrace: true
  });
};

export const instrumentRuntimeWindow = (window: BrowserWindow, label: string) => {
  if (instrumentedWindows.has(window)) {
    return;
  }
  instrumentedWindows.add(window);
  liveTraceTargets.add(window);

  writeRuntimeDiagnostic('window-created', { label, liveTrace: true });
  instrumentSession(window.webContents.session);

  window.webContents.on('did-finish-load', () => {
    writeRuntimeDiagnostic('window-did-finish-load', {
      label,
      url: sanitizeUrl(window.webContents.getURL())
    });
    bootstrapLiveTraceConsole(window);
  });

  window.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedURL, isMainFrame) => {
    writeRuntimeDiagnostic('window-did-fail-load', {
      label,
      errorCode,
      errorDescription: trimText(errorDescription, 2048),
      validatedURL: sanitizeUrl(validatedURL),
      isMainFrame
    });
  });

  window.webContents.on('console-message', (_event, level, message, line, sourceId) => {
    if (
      message.startsWith('[WADDLE-LIVE]')
      || message.startsWith('[WADDLE-DIAG]')
      || message.startsWith('[WADDLE-DIAG-ACTION]')
    ) {
      return;
    }
    if (level < 1 && !/(?:error|warn|fail|missing|exception|timeout)/i.test(message)) {
      return;
    }
    writeRuntimeDiagnostic(level >= 2 ? 'renderer-console-error' : 'renderer-console-warning', {
      label,
      level,
      message: trimText(message, 4096),
      line,
      sourceId: trimText(sourceId, 2048),
      url: sanitizeUrl(window.webContents.getURL())
    });
  });

  window.webContents.on('render-process-gone', (_event, details) => {
    writeRuntimeDiagnostic('render-process-gone', {
      label,
      reason: details.reason
    });
  });

  window.on('unresponsive', () => {
    writeRuntimeDiagnostic('window-unresponsive', {
      label,
      url: sanitizeUrl(window.webContents.getURL())
    });
  });

  const healthTimer = setInterval(() => {
    if (window.isDestroyed() || window.webContents.isDestroyed()) {
      clearInterval(healthTimer);
      liveTraceTargets.delete(window);
      return;
    }
    writeRuntimeDiagnostic('window-health', {
      label,
      url: sanitizeUrl(window.webContents.getURL()),
      loading: window.webContents.isLoading(),
      focused: window.isFocused(),
      visible: window.isVisible()
    });
  }, healthIntervalMs);
  healthTimer.unref();

  window.on('closed', () => {
    clearInterval(healthTimer);
    liveTraceTargets.delete(window);
    writeRuntimeDiagnostic('window-closed', { label });
  });
};
