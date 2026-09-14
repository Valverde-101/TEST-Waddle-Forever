// Command Center runs inside Electron 10 / Chromium 85.
// Element.replaceChildren() is not available until Chromium 86, while the
// enhanced renderer intentionally uses it in several places. Install a tiny
// compatibility shim before commands-static.js executes so the UI cannot die
// during its first render pass.
const elementPrototype = Element.prototype as any;

if (typeof elementPrototype.replaceChildren !== 'function') {
  elementPrototype.replaceChildren = function(this: Element, ...nodes: Array<Node | string>) {
    while (this.firstChild !== null) {
      this.removeChild(this.firstChild);
    }

    for (const node of nodes) {
      this.appendChild(typeof node === 'string' ? document.createTextNode(node) : node);
    }
  };

  console.log('WADDLE_COMMAND_CENTER_COMPAT=PASS replaceChildren=polyfilled chromium=85');
} else {
  console.log('WADDLE_COMMAND_CENTER_COMPAT=PASS replaceChildren=native');
}

// The Command Center may temporarily be opened by a still-running process that
// was started from an isolated .work/build tree while the new exact-SHA files
// have already been live-published to the canonical repository. Keep the base
// fix for every other relative asset, but item PNGs below are resolved through
// the preload from the repository filesystem itself and never depend on this URL.
(() => {
  try {
    const current = new URL(window.location.href);
    if (current.protocol !== 'file:') {
      console.log(`WADDLE_COMMAND_CENTER_ASSET_BASE=PASS mode=non-file url=${current.href}`);
      return;
    }

    const transientMarker = '/.work/build/compiled/client/views/commands/';
    const canonicalMarker = '/compiled/client/views/commands/';
    const pathname = current.pathname.replace(/\\/g, '/');
    const transientIndex = pathname.toLowerCase().lastIndexOf(transientMarker);

    if (transientIndex < 0) {
      const canonical = pathname.toLowerCase().lastIndexOf(canonicalMarker) >= 0;
      console.log(`WADDLE_COMMAND_CENTER_ASSET_BASE=PASS mode=${canonical ? 'canonical' : 'unchanged'} url=${current.href}`);
      return;
    }

    const baseUrl = new URL(current.href);
    baseUrl.pathname = `${pathname.slice(0, transientIndex)}${canonicalMarker}`;
    baseUrl.search = '';
    baseUrl.hash = '';

    let base = document.querySelector('base[data-waddle-command-center-base]') as HTMLBaseElement | null;
    if (base === null) {
      base = document.createElement('base');
      base.setAttribute('data-waddle-command-center-base', 'canonical-media');
      document.head.insertBefore(base, document.head.firstChild);
    }
    base.href = baseUrl.href;

    console.log(`WADDLE_COMMAND_CENTER_ASSET_BASE=PASS mode=canonical-rebase from=${current.href} to=${base.href}`);
  } catch (error) {
    console.error(`WADDLE_COMMAND_CENTER_ASSET_BASE=FAIL error=${error instanceof Error ? error.message : String(error)}`);
  }
})();

/**
 * commands-static.js historically assigns a renderer-relative file:// URL to
 * each clothing image. Intercept only those iconspng assignments before the
 * browser starts a request. The preload reads the exact numeric PNG from:
 *   <repository>/media/default/iconspng/<id>.png
 * and returns a data URL. This gives us three guarantees:
 *   1. no .work/build media shadow tree;
 *   2. no renderer-relative drive/path assumptions;
 *   3. canvas preview trimming is origin-safe because the image is a data URL.
 */
(() => {
  try {
    const descriptor = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
    const nativeGet = descriptor && descriptor.get;
    const nativeSet = descriptor && descriptor.set;
    if (typeof nativeGet !== 'function' || typeof nativeSet !== 'function') {
      console.warn('WADDLE_COMMAND_CENTER_ICON_INTERCEPT=WARN reason=src_descriptor_unavailable');
      return;
    }

    const iconPattern = /(?:^|[\\/])iconspng[\\/](\d+)\.png(?:[?#].*)?$/i;

    Object.defineProperty(HTMLImageElement.prototype, 'src', {
      configurable: descriptor ? descriptor.configurable : true,
      enumerable: descriptor ? descriptor.enumerable : true,
      get: nativeGet,
      set: function(this: HTMLImageElement, value: string) {
        const raw = String(value);
        const match = raw.match(iconPattern);
        if (match === null) {
          (nativeSet as any).call(this, value);
          return;
        }

        const api = (window as any).api;
        if (!api || typeof api.resolveItemIcon !== 'function') {
          console.warn(`WADDLE_COMMAND_CENTER_ICON_INTERCEPT=WARN id=${match[1]} reason=preload_resolver_unavailable`);
          (nativeSet as any).call(this, value);
          return;
        }

        const id = Number(match[1]);
        const token = `${id}:${Date.now()}:${Math.random()}`;
        (this as any).__waddleItemIconToken = token;
        this.setAttribute('data-waddle-item-icon-id', String(id));
        this.setAttribute('data-waddle-item-icon-state', 'resolving');

        Promise.resolve(api.resolveItemIcon(id))
          .then((resolved: unknown) => {
            if ((this as any).__waddleItemIconToken !== token) return;
            if (typeof resolved === 'string' && resolved.startsWith('data:image/png;base64,')) {
              this.setAttribute('data-waddle-item-icon-state', 'resolved');
              (nativeSet as any).call(this, resolved);
              return;
            }

            this.setAttribute('data-waddle-item-icon-state', 'missing');
            this.dispatchEvent(new Event('error'));
          })
          .catch((error: unknown) => {
            if ((this as any).__waddleItemIconToken !== token) return;
            this.setAttribute('data-waddle-item-icon-state', 'error');
            console.error(`WADDLE_COMMAND_CENTER_ICON_INTERCEPT=FAIL id=${id} error=${error instanceof Error ? error.message : String(error)}`);
            this.dispatchEvent(new Event('error'));
          });
      }
    });

    console.log('WADDLE_COMMAND_CENTER_ICON_INTERCEPT=PASS source=repository-only transport=data-url');
  } catch (error) {
    console.error(`WADDLE_COMMAND_CENTER_ICON_INTERCEPT=FAIL error=${error instanceof Error ? error.message : String(error)}`);
  }
})();
