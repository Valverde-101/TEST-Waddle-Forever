import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');

let result;
if (process.platform === 'win32') {
  const script = path.join(repo, '.github', 'scripts', 'waddle-start.ps1');
  result = spawnSync('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', script,
  ], {
    cwd: repo,
    stdio: 'inherit',
    env: process.env,
  });
} else {
  result = spawnSync('yarn', ['start:legacy'], {
    cwd: repo,
    stdio: 'inherit',
    shell: true,
    env: process.env,
  });
}

if (result.error) {
  console.error(result.error);
  process.exit(1);
}
process.exit(result.status ?? 1);
