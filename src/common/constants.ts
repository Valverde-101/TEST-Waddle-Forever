import { VERSION } from './version';

export { VERSION };

export const NAME = 'Waddle Forever';

const configuredHttpPort = Number.parseInt(process.env.WADDLE_HTTP_PORT ?? '', 10);
export const HTTP_PORT = Number.isInteger(configuredHttpPort) && configuredHttpPort >= 1024 && configuredHttpPort <= 65533
  ? configuredHttpPort
  : 24105;

export const IS_DEV = process.env.NODE_ENV === 'dev';

export const WEBSITE = 'https://waddleforever.com';
