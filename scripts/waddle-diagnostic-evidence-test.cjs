'use strict';
// Pure regression tests run against the exact JS that Waddle certification
// compiled (not a second, guessed implementation of the TypeScript source).
const assert = require('node:assert/strict');
const evidence = require('../compiled/client/diagnostic-evidence.js');

const now = '2026-09-20T12:43:01.000Z';
function ev(sequence, category, phase, action, extra = {}) {
  return { schema: 'waddle-live-trace/v1', sequence, utc: now,
    category, phase, source: 'test', action, ...extra };
}

const trace = [
  ev(1, 'OTHER', 'error', 'build.info', {
    url: 'http://127.0.0.1:24105/play/v2/client/build.info',
    statusCode: 404, status: 'http-error'
  }),
  ev(2, 'XT', 'error', 's%g#im', { status: 'unhandled-action' }),
  ev(3, 'SWF', 'error', 'map.swf', {
    url: 'http://127.0.0.1:24105/play/v2/content/global/content/map.swf',
    statusCode: 404, status: 'http-error'
  }),
  ev(4, 'OTHER', 'error', 'build.info', {
    url: 'http://127.0.0.1:24105/play/v2/client/build.info',
    statusCode: 404, status: 'http-error'
  }),
  ev(5, 'SWF', 'response', 'party_map.swf', { statusCode: 200, status: 'ok' }),
  ev(6, 'SWF', 'error', 'unrelated.swf', { benign: true, statusCode: 404 })
];
const ranked = evidence.summarizeDiagnosticIncidents(trace);
assert.equal(ranked.length, 3);
assert.equal(ranked[0].action, 's%g#im');
assert.equal(ranked[0].severity, 'actionable');
assert.equal(ranked[1].category, 'SWF');
assert.equal(ranked[2].action, 'build.info');
assert.equal(ranked[2].severity, 'background');
assert.equal(ranked[2].occurrences, 2);
assert.equal(ranked[2].last_sequence, 4);
assert.deepEqual(evidence.summarizeDiagnosticIncidents(trace, 0), []);

const file = ev(8, 'FILE', 'handled', 'play/v2/content/global/content/map.swf', {
  target: 'default/fair2015/compat/FairIslandMap.swf', requestId: 25
});
const otherMap = ev(9, 'FILE', 'error', 'play/v2/content/global/rooms/map.swf', {
  requestId: 25, status: 'not-found'
});
const otherParty = ev(10, 'SWF', 'response', 'party_map.swf', {
  url: 'http://127.0.0.1:24105/play/v2/content/global/close_ups/party_map.swf',
  requestId: 25, statusCode: 200
});
const main = ev(11, 'SWF', 'error', 'map.swf', {
  url: 'http://127.0.0.1:24105/play/v2/content/global/content/map.swf?contentVersion=84421',
  requestId: 25, statusCode: 404
});
const chain = evidence.traceResourceChain(main, [file, otherMap, otherParty, main]);
assert.deepEqual(chain.map(e => e.sequence), [8, 11],
  'a reused request id or the same leaf in another directory must not imply a shared resource');
assert.equal(evidence.isDiagnosticFailure(ev(20, 'SWF', 'error', 'x.swf', { benign: true })), false);
assert.equal(evidence.isDiagnosticFailure(ev(21, 'SWF', 'error', 'x.swf', { error: 'ERR_ABORTED' })), false);
assert.equal(evidence.isDiagnosticFailure(ev(22, 'XT', 'error', 's%fair#fstartgame')), true);
console.log('WADDLE_DIAGNOSTIC_EVIDENCE=PASS triage=true repeated_probes=true exact_route=true benign=false_positives');
