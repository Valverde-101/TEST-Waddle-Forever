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

## Captura correlacionada para fallas visuales de Flash

En el panel integrado pulsa **RECOPILAR JSON + CAPTURA PNG** cuando el problema esté visible (por ejemplo, el mapa de The Fair mostrando iconos que no pertenecen a la época). La captura es una acción **manual**, no una grabación continua. El panel y el botón de diagnóstico se ocultan durante dos frames para no tapar el mapa y se restauran inmediatamente. Se guardan los siguientes archivos en `.work/diagnostics/share`:

- `waddle-share-latest.json`: `last_failure_analysis` conserva el último error cronológico; `primary_failure_analysis` prioriza un error SWF/FILE/XT/XML accionable por encima de 404 auxiliares repetidos, y `incident_summary.ranked` registra todos los grupos con número de ocurrencias, prioridad y secuencia. La ventana de 1500 eventos puede truncar evidencia antigua y se declara en `trace_window`.
- `waddle-share-latest.png`: pantalla del juego en el instante de la exportación. Si Electron no consigue capturar el contenido, el JSON registra `visual_evidence.screenshot.status=unavailable`; en ese caso se adjunta una captura manual.
- `visual_evidence.scene_assets`: rutas exactas, existencia, tamaño y SHA-256 de los SWF de mapa, mapa de evento, nota, Plaza, teatro e icono observados por el servidor. Los archivos originales no se modifican ni se vuelcan completos a la exportación.

**Para encontrar la causa de un defecto exclusivamente visual, adjunta el JSON y la PNG del mismo instante.** Revisa primero la imagen: puede mostrar nombres o información personal visible en el juego. Que un SWF responda HTTP 200 y tenga un hash válido **no demuestra** que sus gráficos internos sean correctos. El diagnóstico no ve directamente el display list, el `onRelease` interno ni los símbolos del SWF: contrasta la captura con la versión histórica mediante FFDec antes de retirar gráficos.

La correlación de red vincula solicitudes únicamente por ruta completa y ventana temporal de diez segundos, nunca por coincidencia del nombre final `map.swf` ni por un XT cercano considerado automáticamente su solicitante. Los 404 auxiliares (`build.info`, `game_configs.bin`) siguen registrados: solo bajan de prioridad y no ocultan errores interactivos. Se retienen tres conjuntos JSON/TXT/PNG completos, sin eliminar los registros de fallos en el JSON.
