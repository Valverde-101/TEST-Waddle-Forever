import fs from 'fs';
import os from 'os';
import path from 'path';
import type { BrowserWindow } from 'electron';

const runtimeLogDirectory = path.join(process.cwd(), '.work', 'logs', 'runtime');
const explicitDiagnosticPath = process.env.WADDLE_RUNTIME_DIAGNOSTIC_LOG?.trim();
const runtimeLeaseRoot = path.join(process.cwd(), '.work', 'state', 'runtime-leases');

const getLatestLauncherStderr = (): string | undefined => {
  try {
    if (!fs.existsSync(runtimeLogDirectory)) {
      return undefined;
    }

    const candidates = fs.readdirSync(runtimeLogDirectory)
      .filter(name => /^client-\d{8}-\d{6}\.stderr\.log$/.test(name))
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
    explicitPath: Boolean(explicitDiagnosticPath)
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

export const instrumentRuntimeWindow = (window: BrowserWindow, label: string) => {
  writeRuntimeDiagnostic('window-created', { label });

  window.webContents.on('did-finish-load', () => {
    writeRuntimeDiagnostic('window-did-finish-load', {
      label,
      url: window.webContents.getURL()
    });
  });

  window.webContents.on('did-fail-load', (_event, errorCode, errorDescription, validatedURL, isMainFrame) => {
    writeRuntimeDiagnostic('window-did-fail-load', {
      label,
      errorCode,
      errorDescription,
      validatedURL,
      isMainFrame
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
      url: window.webContents.getURL()
    });
  });

  window.on('closed', () => {
    writeRuntimeDiagnostic('window-closed', { label });
  });
};
