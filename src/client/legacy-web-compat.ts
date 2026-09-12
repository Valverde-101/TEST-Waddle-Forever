import { BrowserWindow } from 'electron';
import { writeRuntimeDiagnostic } from './runtime-diagnostics';

/**
 * The archived Club Penguin website contains a few legacy AJAX helpers that
 * build local URLs from location.hostname. hostname deliberately excludes the
 * port, which is fatal for Waddle because its local web server uses a dynamic
 * non-default port (for example 24105).
 *
 * Keep the historical media immutable and repair the browser contract at the
 * runtime boundary instead: requests to the same protocol/hostname with an
 * omitted port inherit the current page port. External hosts and explicitly
 * ported URLs are never touched.
 */
export const installLegacyWebCompatibility = async (window: BrowserWindow): Promise<void> => {
  if (window.isDestroyed() || window.webContents.isDestroyed()) return;

  const result = await window.webContents.executeJavaScript(`(() => {
    const marker = '__WADDLE_LEGACY_LOCAL_URL_COMPAT__';
    if (window[marker]) return { installed: true, reused: true };

    const pagePort = window.location.port;
    const pageHostname = window.location.hostname;
    const pageProtocol = window.location.protocol;

    const normalizeLocalUrl = (input) => {
      if (!pagePort || typeof input !== 'string' || input.length === 0) return input;
      try {
        const parsed = new URL(input, window.location.href);
        if (
          parsed.protocol === pageProtocol &&
          parsed.hostname === pageHostname &&
          parsed.port === '' &&
          parsed.origin !== window.location.origin
        ) {
          parsed.port = pagePort;
          return parsed.toString();
        }
      } catch (_) {
        // Preserve the browser's native handling for malformed/relative inputs.
      }
      return input;
    };

    const xhrOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
      const normalized = normalizeLocalUrl(url);
      if (normalized !== url) {
        console.info('[WADDLE-COMPAT] local XHR port restored', url, '->', normalized);
      }
      return xhrOpen.call(this, method, normalized, async, user, password);
    };

    if (typeof window.fetch === 'function') {
      const nativeFetch = window.fetch.bind(window);
      window.fetch = function(input, init) {
        if (typeof input === 'string') {
          const normalized = normalizeLocalUrl(input);
          if (normalized !== input) {
            console.info('[WADDLE-COMPAT] local fetch port restored', input, '->', normalized);
          }
          return nativeFetch(normalized, init);
        }
        return nativeFetch(input, init);
      };
    }

    window[marker] = true;
    return {
      installed: true,
      reused: false,
      origin: window.location.origin,
      port: pagePort
    };
  })()`, true);

  writeRuntimeDiagnostic('legacy-web-compat-ready', result && typeof result === 'object'
    ? result
    : { installed: true });
};
