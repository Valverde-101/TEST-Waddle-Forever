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
// have already been live-published to the canonical repository. Relative media
// URLs must never follow that transient build root: the canonical item PNGs live
// under <repo>/media/default/iconspng.
//
// Install a document base before commands-static.js is parsed. This keeps normal
// canonical execution unchanged, but rebases any dynamic relative asset URL
// from <repo>/.work/build/compiled/... back to <repo>/compiled/... . The existing
// ../../../../media/default/iconspng/<id>.png mapping then resolves to the real
// repository media tree without copying or junctioning thousands of images.
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
