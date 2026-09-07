import fs from 'fs';
import path from 'path';
import type { BrowserWindow } from 'electron';

const runtimeLogDirectory = path.join(process.cwd(), '.work', 'logs', 'runtime');
const explicitDiagnosticPath = process.env.WADDLE_RUNTIME_DIAGNOSTIC_LOG?.trim();

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

    // The launcher creates the marker immediately before Electron starts.
    // Avoid ever attaching a new process to an old diagnostic log.
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

let diagnosticsInstalled = false;

export const installRuntimeDiagnostics = () => {
  if (diagnosticsInstalled) {
    return diagnosticPath;
  }

  // When the managed launcher supplied an exact file, failure to write the very
  // first event is a launch failure, not something to hide. This makes the
  // health contract deterministic while retaining best-effort logging for raw
  // developer launches that do not provide WADDLE_RUNTIME_DIAGNOSTIC_LOG.
  appendRuntimeDiagnostic('main-process-boot', {
    electron: process.versions.electron ?? null,
    chromium: process.versions.chrome ?? null,
    node: process.versions.node,
    cwd: process.cwd(),
    explicitPath: Boolean(explicitDiagnosticPath)
  }, Boolean(explicitDiagnosticPath));

  process.on('unhandledRejection', reason => {
    writeRuntimeDiagnostic('unhandled-rejection', serializeError(reason));
  });

  process.on('uncaughtException', error => {
    writeRuntimeDiagnostic('uncaught-exception', serializeError(error));
    // Continuing after an uncaught exception can leave the embedded server and
    // Flash runtime in a corrupt state. Preserve evidence and fail explicitly.
    process.exit(1);
  });

  diagnosticsInstalled = true;
  return diagnosticPath;
};

// main.ts imports this module before every project dependency. Initializing at
// module evaluation time ensures we can observe failures or stalls that happen
// while later CommonJS imports are being evaluated, before main.ts body runs.
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