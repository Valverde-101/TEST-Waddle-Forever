import path from 'path';
import Module from 'module';

type ModuleRuntime = typeof Module & {
  _initPaths?: () => void;
  globalPaths?: string[];
};

/**
 * Reinitialize Node's global module search paths when Waddle executes compiled
 * code from the external Electron runtime while dependencies remain physically
 * in the repository's single node_modules tree.
 *
 * Electron 10 embeds Node 12. Setting NODE_PATH in the parent PowerShell
 * process is not sufficient for all Electron entry modes: the embedded module
 * loader can retain globalPaths created before that environment value is
 * observed. Re-running Module._initPaths() makes bare imports such as
 * require('express') resolve through the canonical repository dependency tree
 * without copying node_modules into .work or a runtime snapshot.
 */
export function initializeRuntimeNodePath(): void {
  const configured = process.env.WADDLE_RUNTIME_NODE_MODULES
    || process.env.WADDLE_NODE_MODULES
    || process.env.NODE_PATH;

  if (!configured) {
    return;
  }

  const canonical = path.resolve(configured.split(path.delimiter)[0]);
  const existing = (process.env.NODE_PATH || '')
    .split(path.delimiter)
    .map(value => value.trim())
    .filter(Boolean);

  const nodePaths = [canonical, ...existing.filter(value => path.resolve(value) !== canonical)];
  process.env.NODE_PATH = nodePaths.join(path.delimiter);

  const runtimeModule = Module as ModuleRuntime;
  if (typeof runtimeModule._initPaths !== 'function') {
    throw new Error('WADDLE_RUNTIME_MODULE_PATH=FAIL Module._initPaths unavailable');
  }
  runtimeModule._initPaths();

  const resolved = (runtimeModule.globalPaths || []).some(value => path.resolve(value) === canonical);
  if (!resolved) {
    throw new Error(`WADDLE_RUNTIME_MODULE_PATH=FAIL canonical_path_not_active path=${canonical}`);
  }

  process.env.WADDLE_RUNTIME_MODULE_PATH_READY = '1';
}

initializeRuntimeNodePath();
