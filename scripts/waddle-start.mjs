import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');

if (process.platform !== 'win32') {
  console.error(`WADDLE_PLATFORM=FAIL windows_required actual=${process.platform}`);
  process.exit(1);
}
if (process.arch !== 'x64') {
  console.error(`WADDLE_PLATFORM=FAIL windows_x64_required actual=${process.arch}`);
  process.exit(1);
}

const script = path.join(repo, '.github', 'scripts', 'waddle-start.ps1');
const result = spawnSync('powershell.exe', [
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', script,
], {
  cwd: repo,
  stdio: 'inherit',
  env: process.env,
});

if (result.error) {
  console.error(result.error);
  process.exit(1);
}
process.exit(result.status ?? 1);
