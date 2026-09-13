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
