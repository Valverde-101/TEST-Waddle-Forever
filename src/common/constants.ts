import { VERSION } from './version';

export { VERSION };

export const NAME = 'Waddle Forever';

function getNonInteractiveHttpPort(): number {
  const seedText = process.env.GITHUB_RUN_ID ?? String(process.pid);
  let seed = 0;
  for (const char of seedText) {
    seed = ((seed * 33) + char.charCodeAt(0)) >>> 0;
  }
  // Reserve a 3-port block (HTTP, login, world) well away from the normal
  // interactive 24105-24107 range. This lets exact-SHA certification coexist
  // with a live preview without stealing its sockets.
  return 30000 + ((seed % 10000) * 3);
}

const configuredHttpPort = Number.parseInt(process.env.WADDLE_HTTP_PORT ?? '', 10);
const defaultHttpPort = process.env.WADDLE_NONINTERACTIVE === '1'
  ? getNonInteractiveHttpPort()
  : 24105;
export const HTTP_PORT = Number.isInteger(configuredHttpPort) && configuredHttpPort >= 1024 && configuredHttpPort <= 65533
  ? configuredHttpPort
  : defaultHttpPort;

export const IS_DEV = process.env.NODE_ENV === 'dev';

export const WEBSITE = 'https://waddleforever.com';
