# Waddle diagnostics

`Waddle-Diagnose.cmd` correlates the live Electron/Flash trace with the incremental FFDec/SWF analysis without modifying original SWFs or copying the runtime.

## Always-on runtime telemetry

`src/client/runtime-diagnostics.ts` records JSONL events in `.work/logs/runtime` for:

- Electron main/renderer failures and unhandled exceptions.
- Main/setup window lifecycle and one-minute health snapshots.
- Renderer console warnings/errors.
- HTTP/resource failures, 4xx/5xx responses and slow requests.
- SWF/XML/JSON/script/object/XHR/WebSocket-relevant resource responses.
- Runtime lease health and Flash readiness events emitted by the existing launcher/main process.

Sensitive query parameters whose names resemble passwords, tokens, authentication, sessions, secrets or keys are redacted before they are written.

## Static + dynamic correlation

The existing `.work/swf-analysis` pipeline remains authoritative for static SWF inventory, hashes, FFDec dumps, dependency edges, literal SWF references, protocol/URL discovery and Flash runtime trace. `Waddle-Diagnose.cmd` reads that data and the newest runtime JSONL log, then writes:

- `.work/diagnostics/latest/summary.json`
- `.work/diagnostics/latest/issues.json`
- `.work/diagnostics/latest/runtime-events.json`
- `.work/diagnostics/latest/resource-failures.json`
- `.work/diagnostics/latest/slow-resources.json`
- `.work/diagnostics/latest/swf-unresolved.json`
- `.work/diagnostics/latest/report.txt`

Only the three newest timestamped diagnostic runs are retained.

A statically unresolved SWF whose filename also fails dynamically is promoted to a critical `swf-static-runtime-correlation` issue. Fatal renderer/Flash/service events are also critical. Static unresolved references by themselves remain warnings because literal strings can be optional, generated or historical.

Use `Waddle-Diagnose.cmd -FailOnCritical` when a non-zero exit code is required for a strict gate.
