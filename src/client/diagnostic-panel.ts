import fs from 'fs';
import path from 'path';
import { BrowserWindow, shell } from 'electron';
import type { WaddleLiveTraceEvent } from '@common/live-trace';
import { writeRuntimeDiagnostic } from './runtime-diagnostics';

const workRoot = path.join(process.cwd(), '.work');
const swfAnalysisRoot = path.join(workRoot, 'swf-analysis');
const diagnosticsRoot = path.join(workRoot, 'diagnostics');
const shareRoot = path.join(diagnosticsRoot, 'share');
const consoleHistoryLimit = 600;

const recentConsoleMessages: Array<Record<string, unknown>> = [];

type JsonRecord = Record<string, unknown>;
type ManifestEntry = JsonRecord & { sha256?: string; path?: string };
type MissingSwfEntry = JsonRecord & { leaf?: string; reference?: string; source?: string };
type DependencyEdge = JsonRecord & { reference?: string; target?: string; source?: string };
type FfdecHit = { dump: string; sha256: string; source_paths: string[] };

type FailureStaticEvidence = {
  requested_leaf: string;
  manifest_matches: ManifestEntry[];
  missing_reference_matches: MissingSwfEntry[];
  dependency_matches: DependencyEdge[];
  requested_by_candidates: string[];
  ffdec_text_matches: FfdecHit[];
  server_file_resolution: WaddleLiveTraceEvent[];
};

type FailureAnalysis = {
  schema: 'waddle-failure-analysis/v1';
  found: boolean;
  classification: string;
  confidence: string;
  message?: string;
  generated_utc?: string;
  explanation?: string;
  recommended_action?: string;
  failure?: WaddleLiveTraceEvent;
  request_chain?: WaddleLiveTraceEvent[];
  context?: WaddleLiveTraceEvent[];
  preceding_protocol_event?: WaddleLiveTraceEvent | null;
  static?: FailureStaticEvidence;
  likely_requester?: string | null;
  file_resolution?: WaddleLiveTraceEvent | null;
};

type DiagnosticPanelVerification = {
  toggle: boolean;
  panel: boolean;
  traceButton: boolean;
  collectButton: boolean;
  resultBridge: boolean;
};

const validTracePhases = new Set(['request', 'response', 'handled', 'error', 'state']);
const sensitiveDiagnosticKey = /^(?:pass|password|passwd|token|authorization|auth|session|secret|cookie|api[_-]?key|body|payload)$/i;
const structuredBodyKey = /^(?:request|response|raw|message)(?:body|payload)$/i;
const delimitedBodyKey = /(?:^|[_-])(?:body|payload)$/i;
const unsafeObjectKey = /^(?:__proto__|prototype|constructor)$/;
const maxSanitizeArrayLength = 2000;
const maxSanitizeDepth = 10;

const isRecord = (value: unknown): value is JsonRecord => (
  typeof value === 'object' && value !== null && !Array.isArray(value)
);

const isWaddleLiveTraceEvent = (value: unknown): value is WaddleLiveTraceEvent => {
  if (!isRecord(value)) return false;
  return value.schema === 'waddle-live-trace/v1'
    && typeof value.sequence === 'number'
    && typeof value.utc === 'string'
    && typeof value.category === 'string'
    && typeof value.phase === 'string'
    && validTracePhases.has(value.phase)
    && typeof value.source === 'string';
};

const asRecordArray = <T extends JsonRecord>(value: unknown): T[] => {
  if (Array.isArray(value)) return value.filter(isRecord).map(item => item as T);
  if (isRecord(value)) return [value as T];
  return [];
};

const readJsonSafe = (filePath: string, fallback: unknown = null): unknown => {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as unknown;
  } catch {
    return fallback;
  }
};

const tailTextFile = (filePath: string | null, maxLines: number) => {
  if (!filePath) return [] as string[];
  try {
    const text = fs.readFileSync(filePath, 'utf8');
    const lines = text.split(/\r?\n/).filter(Boolean);
    return lines.slice(-maxLines);
  } catch {
    return [] as string[];
  }
};

const leafName = (value: unknown) => {
  const text = String(value ?? '').split('?')[0].replace(/\\/g, '/');
  const parts = text.split('/').filter(Boolean);
  return (parts[parts.length - 1] || text).toLowerCase();
};

const sanitizeDiagnosticText = (value: unknown) => {
  let text = String(value ?? '');
  text = text.replace(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi, 'Bearer [redacted]');
  text = text.replace(/((?:password|passwd|token|authorization|auth|session|secret|api[_-]?key|cookie)\s*[=:]\s*)([^\s&;"']+)/gi, '$1[redacted]');
  text = text.replace(/([?&](?:password|passwd|token|authorization|auth|session|secret|api[_-]?key)=)([^&#\s]+)/gi, '$1[redacted]');
  return text.length > 16000 ? `${text.slice(0, 16000)}...[truncated]` : text;
};

const isSensitiveDiagnosticKey = (keyName: string) => (
  sensitiveDiagnosticKey.test(keyName) || structuredBodyKey.test(keyName) || delimitedBodyKey.test(keyName)
);

const sanitizeValue = <T>(
  value: T,
  keyName = '',
  depth = 0,
  seen: WeakSet<object> = new WeakSet<object>()
): T => {
  if (isSensitiveDiagnosticKey(keyName)) return '[redacted]' as unknown as T;
  if (value === null || value === undefined || typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'string') return sanitizeDiagnosticText(value) as unknown as T;
  if (typeof value === 'bigint') return value.toString() as unknown as T;
  if (typeof value === 'function' || typeof value === 'symbol') return `[${typeof value}]` as unknown as T;
  if (depth >= maxSanitizeDepth) return '[max-depth]' as unknown as T;

  if (typeof value === 'object') {
    const objectValue = value as object;
    if (seen.has(objectValue)) return '[circular]' as unknown as T;
    seen.add(objectValue);

    if (Array.isArray(value)) {
      return value
        .slice(0, maxSanitizeArrayLength)
        .map(item => sanitizeValue(item, '', depth + 1, seen)) as unknown as T;
    }

    const out = Object.create(null) as JsonRecord;
    for (const [key, child] of Object.entries(value as JsonRecord)) {
      if (unsafeObjectKey.test(key)) continue;
      out[key] = sanitizeValue(child, key, depth + 1, seen);
    }
    return out as unknown as T;
  }

  return sanitizeDiagnosticText(String(value)) as unknown as T;
};

const findLatestRuntimeLog = () => {
  const runtimeRoot = path.join(workRoot, 'logs', 'runtime');
  try {
    if (!fs.existsSync(runtimeRoot)) return null;
    const candidates = fs.readdirSync(runtimeRoot)
      .filter(name => /^client-.*\.stderr\.log$/i.test(name) || name === 'application-errors.log')
      .map(name => {
        const fullPath = path.join(runtimeRoot, name);
        return { fullPath, mtime: fs.statSync(fullPath).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime);
    return candidates[0]?.fullPath ?? null;
  } catch {
    return null;
  }
};

const isFailureEvent = (event: WaddleLiveTraceEvent) => {
  const phase = event.phase.toLowerCase();
  const statusCode = Number(event.statusCode || 0);
  const status = String(event.status || '').toLowerCase();
  const error = String(event.error || '').toUpperCase();
  if (status === 'aborted' || error.includes('ERR_ABORTED')) return false;
  if (phase === 'error' || statusCode >= 400) return true;
  return [
    'unhandled-action',
    'unhandled-context',
    'invalid-signature',
    'send-failed',
    'handler-threw',
    'network-error',
    'http-error'
  ].includes(status);
};

const findLastFailure = (trace: WaddleLiveTraceEvent[]) => {
  for (let i = trace.length - 1; i >= 0; i -= 1) {
    if (isFailureEvent(trace[i])) return trace[i];
  }
  return null;
};

const searchFfdecText = (leaf: string, manifest: ManifestEntry[]): FfdecHit[] => {
  if (!leaf) return [];
  const dumpRoot = path.join(swfAnalysisRoot, 'ffdec');
  try {
    if (!fs.existsSync(dumpRoot)) return [];
    const needle = leaf.toLowerCase();
    const hits: FfdecHit[] = [];
    for (const name of fs.readdirSync(dumpRoot).filter(name => /\.(?:as2|as3)\.txt$/i.test(name)).slice(0, 1500)) {
      if (hits.length >= 20) break;
      const fullPath = path.join(dumpRoot, name);
      const stat = fs.statSync(fullPath);
      if (stat.size > 8 * 1024 * 1024) continue;
      let text = '';
      try { text = fs.readFileSync(fullPath, 'utf8'); } catch { continue; }
      if (!text.toLowerCase().includes(needle)) continue;
      const hash = name.split('.')[0].toLowerCase();
      const sourcePaths = manifest
        .filter(item => String(item.sha256 || '').toLowerCase() === hash)
        .map(item => item.path)
        .filter((sourcePath): sourcePath is string => Boolean(sourcePath))
        .slice(0, 10);
      hits.push({ dump: name, sha256: hash, source_paths: sourcePaths });
    }
    return hits;
  } catch {
    return [];
  }
};

const buildFailureAnalysis = (
  failure: WaddleLiveTraceEvent | null,
  trace: WaddleLiveTraceEvent[]
): FailureAnalysis => {
  if (!failure) {
    return {
      schema: 'waddle-failure-analysis/v1',
      found: false,
      classification: 'NO_FAILURE_OBSERVED',
      confidence: 'high',
      message: 'No se encontró una falla en el historial live trace actual.'
    };
  }

  const sequence = Number(failure.sequence || 0);
  const foundIndex = trace.findIndex(event => Number(event.sequence || 0) === sequence);
  const index = foundIndex < 0 ? trace.length - 1 : foundIndex;
  const context = trace.slice(Math.max(0, index - 18), Math.min(trace.length, index + 9));
  const requestId = failure.requestId;
  const requestChain = requestId === undefined
    ? []
    : trace.filter(event => String(event.requestId ?? '') === String(requestId)).slice(-20);
  const precedingProtocol = context.slice(0, Math.max(0, context.length - 1)).reverse().find(event => {
    const category = event.category.toUpperCase();
    return category === 'XT' || category === 'XML';
  }) || null;

  const category = failure.category.toUpperCase();
  const action = String(failure.action || '');
  const leaf = leafName(action || failure.url || '');
  const statusCode = Number(failure.statusCode || 0);

  const manifest = asRecordArray<ManifestEntry>(readJsonSafe(path.join(swfAnalysisRoot, 'manifest.json'), []));
  const missing = asRecordArray<MissingSwfEntry>(readJsonSafe(path.join(swfAnalysisRoot, 'missing-swfs.json'), []));
  const edges = asRecordArray<DependencyEdge>(readJsonSafe(path.join(swfAnalysisRoot, 'dependency-graph.json'), []));

  const manifestMatches = category === 'SWF' && leaf
    ? manifest.filter(item => leafName(item.path) === leaf).slice(0, 30)
    : [];
  const missingMatches = category === 'SWF' && leaf
    ? missing.filter(item => leafName(item.leaf || item.reference) === leaf).slice(0, 30)
    : [];
  const edgeMatches = category === 'SWF' && leaf
    ? edges.filter(item => leafName(item.reference) === leaf || leafName(item.target) === leaf).slice(0, 50)
    : [];
  const serverFileResolution = leaf
    ? trace.filter(event => event.category.toUpperCase() === 'FILE' && leafName(event.action || event.url || '') === leaf).slice(-30)
    : [];
  const fileResolution = [...serverFileResolution].reverse().find(event => event.phase === 'error')
    || [...serverFileResolution].reverse().find(event => Boolean(event.status))
    || null;
  const fileResolutionStatus = String(fileResolution?.status || '').toLowerCase();

  const requestedByCandidates = Array.from(new Set([
    ...missingMatches.map(item => String(item.source || '')),
    ...edgeMatches.map(item => String(item.source || ''))
  ].filter(Boolean))).slice(0, 20);
  const ffdecTextMatches = category === 'SWF' && leaf ? searchFfdecText(leaf, manifest) : [];
  for (const hit of ffdecTextMatches) {
    for (const sourcePath of hit.source_paths) {
      if (sourcePath && !requestedByCandidates.includes(sourcePath)) requestedByCandidates.push(sourcePath);
    }
  }

  let classification = 'RUNTIME_FAILURE';
  let confidence = 'medium';
  let explanation = 'Se observó una falla en tiempo real.';
  let recommendedAction = 'Revisar el contexto y los eventos correlacionados.';

  if (category === 'SWF' && statusCode === 404) {
    if (/^(?:unsafe-|read-failed|serve-failed)/.test(fileResolutionStatus)) {
      classification = 'SWF_LOCAL_RESOLUTION_FAILURE';
      confidence = 'high';
      explanation = `El SWF ${leaf} devolvió 404 y el resolvedor local reportó ${fileResolutionStatus}.`;
      recommendedAction = 'Revisar el target/resolver mostrado por el panel antes de copiar archivos; la falla está en resolución/lectura local.';
    } else if (manifestMatches.length > 0) {
      classification = 'SWF_ROUTE_OR_VERSION_MISMATCH';
      confidence = 'high';
      explanation = `El servidor devolvió 404 para ${leaf}, pero existe al menos una copia con ese nombre en el inventario SWF.`;
      recommendedAction = 'Comparar la URL solicitada con las rutas existentes; corregir routing, versión/timeline o resolución de idioma antes de copiar archivos.';
    } else if (missingMatches.length > 0 || requestedByCandidates.length > 0) {
      classification = 'SWF_MISSING_REFERENCED_ASSET';
      confidence = 'high';
      explanation = `${leaf} fue solicitado y no existe en el inventario; además hay evidencia estática que apunta a quién lo referencia.`;
      recommendedAction = 'Abrir primero los SWF de requested_by_candidates en FFDec y revisar cómo construyen/cargan el nombre antes de agregar un asset.';
    } else {
      classification = 'SWF_MISSING_OR_DYNAMIC_REFERENCE';
      confidence = fileResolutionStatus === 'not-found' ? 'high' : 'medium';
      explanation = `${leaf} devolvió 404 y el resolvedor local no encontró un asset utilizable ni una referencia estática conocida.`;
      recommendedAction = 'Usar el contexto XT/XML, la ruta del resolvedor FILE y los eventos anteriores para localizar idioma, sala o timeline que construyó la solicitud.';
    }
  } else if (category === 'SWF' && statusCode >= 500) {
    classification = 'SWF_SERVER_FAILURE';
    confidence = 'high';
    explanation = `El SWF ${leaf} fue solicitado, pero el servidor respondió ${statusCode}.`;
    recommendedAction = 'Revisar el handler HTTP/local de contenido y el mapeo al filesystem.';
  } else if (category === 'SWF' && String(failure.status || '') === 'network-error') {
    classification = 'SWF_NETWORK_FAILURE';
    confidence = 'high';
    explanation = `La carga de ${leaf} falló antes de recibir una respuesta HTTP válida.`;
    recommendedAction = 'Revisar servidor local, socket, cierre de conexión y ruta solicitada.';
  } else if (category === 'FILE') {
    const status = String(failure.status || failure.phase || 'failure').toUpperCase().replace(/[^A-Z0-9]+/g, '_');
    classification = `LOCAL_FILE_${status}`;
    confidence = 'high';
    explanation = `El resolvedor local reportó ${failure.status || failure.phase} para ${action || '(ruta desconocida)'}.`;
    recommendedAction = 'Revisar resolver, target, timeline/mod y el evento SWF/HTTP correlacionado en el mismo contexto.';
  } else if (category === 'XT' || category === 'XML') {
    classification = `SERVER_${String(failure.status || failure.phase || 'ACTION_FAILURE').toUpperCase().replace(/[^A-Z0-9]+/g, '_')}`;
    confidence = 'high';
    explanation = `La acción ${category} ${action || '(sin nombre)'} falló o quedó sin manejar.`;
    recommendedAction = 'Revisar el handler, contexto, firma de argumentos y respuesta asociada en el servidor Waddle.';
  }

  return sanitizeValue<FailureAnalysis>({
    schema: 'waddle-failure-analysis/v1',
    found: true,
    generated_utc: new Date().toISOString(),
    classification,
    confidence,
    explanation,
    recommended_action: recommendedAction,
    failure,
    request_chain: requestChain,
    context,
    preceding_protocol_event: precedingProtocol,
    static: {
      requested_leaf: leaf,
      manifest_matches: manifestMatches,
      missing_reference_matches: missingMatches,
      dependency_matches: edgeMatches,
      requested_by_candidates: requestedByCandidates,
      ffdec_text_matches: ffdecTextMatches,
      server_file_resolution: serverFileResolution
    },
    likely_requester: requestedByCandidates[0] || precedingProtocol?.action || null,
    file_resolution: fileResolution
  });
};

const getRendererTrace = async (window: BrowserWindow): Promise<WaddleLiveTraceEvent[]> => {
  if (window.isDestroyed() || window.webContents.isDestroyed()) return [];
  try {
    const value: unknown = await window.webContents.executeJavaScript(
      'Array.isArray(window.__WADDLE_LIVE_TRACE__) ? window.__WADDLE_LIVE_TRACE__.slice(-1500) : []',
      true
    );
    return Array.isArray(value) ? value.filter(isWaddleLiveTraceEvent) : [];
  } catch {
    return [];
  }
};

const sendPanelResult = (window: BrowserWindow, payload: unknown) => {
  if (window.isDestroyed() || window.webContents.isDestroyed()) return;
  const serialized = JSON.stringify(sanitizeValue(payload)).replace(/</g, '\\u003c');
  void window.webContents.executeJavaScript(
    `typeof window.__WADDLE_DIAG_SET_RESULT__ === 'function' && window.__WADDLE_DIAG_SET_RESULT__(${serialized})`,
    true
  ).catch(() => undefined);
};

const collectShareBundle = async (window: BrowserWindow) => {
  const trace = await getRendererTrace(window);
  const failure = findLastFailure(trace);
  const failureAnalysis = buildFailureAnalysis(failure, trace);
  const runtimeLog = findLatestRuntimeLog();
  const fileResolutionEvents = trace.filter(event => event.category.toUpperCase() === 'FILE').slice(-300);

  const bundle = sanitizeValue({
    schema: 'waddle-share-diagnostics/v2',
    generated_utc: new Date().toISOString(),
    versions: {
      electron: process.versions.electron || null,
      chrome: process.versions.chrome || null,
      node: process.versions.node || null
    },
    current_url: window.webContents.getURL(),
    last_failure_analysis: failureAnalysis,
    live_trace: trace,
    file_resolution: fileResolutionEvents,
    renderer_console: recentConsoleMessages.slice(-500),
    runtime_log_name: runtimeLog ? path.basename(runtimeLog) : null,
    runtime_log_tail: tailTextFile(runtimeLog, 1400),
    diagnostics: {
      summary: readJsonSafe(path.join(diagnosticsRoot, 'latest', 'summary.json')),
      issues: readJsonSafe(path.join(diagnosticsRoot, 'latest', 'issues.json'), []),
      resource_failures: readJsonSafe(path.join(diagnosticsRoot, 'latest', 'resource-failures.json'), []),
      file_resolution: readJsonSafe(path.join(diagnosticsRoot, 'latest', 'file-resolution.json'), []),
      file_resolution_errors: readJsonSafe(path.join(diagnosticsRoot, 'latest', 'file-resolution-errors.json'), []),
      slow_resources: readJsonSafe(path.join(diagnosticsRoot, 'latest', 'slow-resources.json'), []),
      report: tailTextFile(path.join(diagnosticsRoot, 'latest', 'report.txt'), 400)
    },
    swf_analysis: {
      summary: readJsonSafe(path.join(swfAnalysisRoot, 'summary.json')),
      runtime_priority: readJsonSafe(path.join(swfAnalysisRoot, 'runtime-priority.json'), []),
      runtime_trace: readJsonSafe(path.join(swfAnalysisRoot, 'runtime-trace.json')),
      last_failure_static: failureAnalysis.static ?? null
    }
  });

  fs.mkdirSync(shareRoot, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const jsonPath = path.join(shareRoot, `waddle-share-${stamp}.json`);
  const txtPath = path.join(shareRoot, `waddle-share-${stamp}.txt`);
  const latestJson = path.join(shareRoot, 'waddle-share-latest.json');
  const latestTxt = path.join(shareRoot, 'waddle-share-latest.txt');

  const analysis = bundle.last_failure_analysis;
  const summaryLines = [
    'WADDLE DIAGNOSTIC SHARE',
    `Generated UTC: ${bundle.generated_utc}`,
    `Classification: ${analysis.classification || 'NO_FAILURE_OBSERVED'}`,
    `Confidence: ${analysis.confidence || 'n/a'}`,
    `Failure: ${analysis.failure?.category || ''} ${analysis.failure?.action || ''} status=${analysis.failure?.statusCode || analysis.failure?.status || ''}`.trim(),
    `Local resolver: ${analysis.file_resolution?.status || 'n/a'} ${analysis.file_resolution?.resolver || ''} ${analysis.file_resolution?.target || ''}`.trim(),
    `Likely requester: ${analysis.likely_requester || 'unknown'}`,
    `Explanation: ${analysis.explanation || analysis.message || ''}`,
    `Recommended action: ${analysis.recommended_action || ''}`,
    `Live trace events: ${trace.length}`,
    `File resolution events: ${fileResolutionEvents.length}`,
    `Renderer console events: ${recentConsoleMessages.length}`,
    '',
    'Share the JSON file for full evidence. The TXT file is a compact summary.'
  ];

  fs.writeFileSync(jsonPath, JSON.stringify(bundle, null, 2), 'utf8');
  fs.writeFileSync(txtPath, summaryLines.join('\r\n'), 'utf8');
  fs.copyFileSync(jsonPath, latestJson);
  fs.copyFileSync(txtPath, latestTxt);

  try {
    const timestamped = fs.readdirSync(shareRoot)
      .filter(name => /^waddle-share-\d.*\.(?:json|txt)$/i.test(name))
      .map(name => {
        const fullPath = path.join(shareRoot, name);
        return { fullPath, mtime: fs.statSync(fullPath).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime);
    for (const stale of timestamped.slice(6)) {
      try {
        fs.unlinkSync(stale.fullPath);
      } catch {
        // Retention cleanup is best-effort; a locked stale bundle must not block export.
      }
    }
  } catch {
    // Retention cleanup is best-effort; the newly generated diagnostic remains valid.
  }

  shell.showItemInFolder(latestJson);
  return {
    schema: 'waddle-share-result/v1',
    ok: true,
    classification: analysis.classification || 'NO_FAILURE_OBSERVED',
    confidence: analysis.confidence || 'n/a',
    latest_json: path.relative(process.cwd(), latestJson),
    latest_txt: path.relative(process.cwd(), latestTxt),
    timestamped_json: path.relative(process.cwd(), jsonPath),
    message: 'Diagnóstico recopilado. Se abrió la carpeta; comparte waddle-share-latest.json para analizar el problema completo.'
  };
};

const diagnosticPanelCss = `
#waddle-diagnostic-toggle{position:fixed;right:12px;top:52px;z-index:2147483647;border:1px solid #50d8ff;background:#071a28;color:#dff8ff;border-radius:8px;padding:8px 12px;font:700 12px Arial,sans-serif;cursor:pointer;box-shadow:0 2px 10px #0009}
#waddle-diagnostic-panel{position:fixed;right:12px;top:92px;z-index:2147483647;width:390px;max-height:72vh;overflow:auto;background:#071018f2;color:#e7f7ff;border:1px solid #3a7896;border-radius:10px;box-shadow:0 8px 30px #000c;font:12px Arial,sans-serif;padding:12px;display:none}
#waddle-diagnostic-panel *{box-sizing:border-box}
#waddle-diagnostic-panel .wd-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px}.wd-title{font-size:15px;font-weight:700}.wd-close{background:transparent;border:0;color:#fff;font-size:18px;cursor:pointer}
#waddle-diagnostic-panel .wd-stats{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;margin:8px 0}.wd-stat{background:#102634;border:1px solid #204b64;border-radius:6px;padding:7px;text-align:center}.wd-num{display:block;font-size:16px;font-weight:700}.wd-label{opacity:.75;font-size:10px}
#waddle-diagnostic-panel button.wd-primary,#waddle-diagnostic-panel button.wd-secondary{width:100%;border-radius:7px;padding:9px 8px;margin-top:7px;font-weight:700;cursor:pointer}.wd-primary{background:#0bb8e8;border:1px solid #62e3ff;color:#03131b}.wd-secondary{background:#3a2712;border:1px solid #e7a14b;color:#ffe7c6}
#waddle-diagnostic-panel .wd-help{opacity:.75;line-height:1.35;margin:8px 0}.wd-result{white-space:pre-wrap;word-break:break-word;background:#02080d;border:1px solid #183747;border-radius:7px;padding:8px;min-height:72px;max-height:280px;overflow:auto;margin-top:8px;color:#d7f2ff}.wd-error{color:#ff827c}.wd-ok{color:#79f2a8}
`;

const installPanelIntoRenderer = (window: BrowserWindow): Promise<DiagnosticPanelVerification> => {
  if (window.isDestroyed() || window.webContents.isDestroyed()) {
    return Promise.reject(new Error('WADDLE_DIAGNOSTIC_PANEL=FAIL renderer_destroyed'));
  }
  const css = JSON.stringify(diagnosticPanelCss);
  const script = `(() => {
    const NL = String.fromCharCode(10);
    const verify = () => ({
      toggle: Boolean(document.getElementById('waddle-diagnostic-toggle')),
      panel: Boolean(document.getElementById('waddle-diagnostic-panel')),
      traceButton: Boolean(document.getElementById('wd-trace')),
      collectButton: Boolean(document.getElementById('wd-collect')),
      resultBridge: typeof window.__WADDLE_DIAG_SET_RESULT__ === 'function'
    });
    if (document.getElementById('waddle-diagnostic-toggle')) return verify();
    const style = document.createElement('style');
    style.id = 'waddle-diagnostic-style';
    style.textContent = ${css};
    document.documentElement.appendChild(style);

    const toggle = document.createElement('button');
    toggle.id = 'waddle-diagnostic-toggle';
    toggle.textContent = 'DIAGNOSTICO';
    document.body.appendChild(toggle);

    const panel = document.createElement('div');
    panel.id = 'waddle-diagnostic-panel';
    panel.innerHTML = '<div class="wd-head"><div class="wd-title">Waddle - Diagnóstico en vivo</div><button class="wd-close" title="Cerrar">×</button></div>' +
      '<div class="wd-help">Rastrea errores SWF/HTTP/FILE/XT/XML y genera un paquete sanitizado con consola, live trace y análisis para compartir.</div>' +
      '<div class="wd-stats"><div class="wd-stat"><span id="wd-errors" class="wd-num wd-error">0</span><span class="wd-label">FALLAS</span></div><div class="wd-stat"><span id="wd-swf" class="wd-num">0</span><span class="wd-label">SWF</span></div><div class="wd-stat"><span id="wd-events" class="wd-num">0</span><span class="wd-label">EVENTOS</span></div></div>' +
      '<button id="wd-collect" class="wd-primary">RECOPILAR PARA COMPARTIR</button>' +
      '<button id="wd-trace" class="wd-secondary">RASTREAR ÚLTIMA FALLA</button>' +
      '<div id="wd-result" class="wd-result">Sin análisis todavía.</div>';
    document.body.appendChild(panel);

    const result = panel.querySelector('#wd-result');
    const renderResult = (payload) => {
      if (!payload) { result.textContent = 'Sin resultado.'; return; }
      if (payload.schema === 'waddle-share-result/v1') {
        result.textContent = payload.message + NL + NL + 'JSON: ' + payload.latest_json + NL + 'TXT: ' + payload.latest_txt + NL + 'Clasificación: ' + payload.classification + ' (' + payload.confidence + ')';
        return;
      }
      const lines = [];
      lines.push('Clasificación: ' + (payload.classification || 'n/a'));
      lines.push('Confianza: ' + (payload.confidence || 'n/a'));
      if (payload.failure) lines.push('Falla: ' + (payload.failure.category || '') + ' ' + (payload.failure.action || '') + ' status=' + (payload.failure.statusCode || payload.failure.status || ''));
      if (payload.file_resolution) lines.push('Resolvedor local: ' + (payload.file_resolution.status || '') + ' via=' + (payload.file_resolution.resolver || '') + ' target=' + (payload.file_resolution.target || ''));
      if (payload.likely_requester) lines.push('Probable solicitante: ' + payload.likely_requester);
      if (payload.explanation) lines.push('Causa probable: ' + payload.explanation);
      if (payload.message && !payload.explanation) lines.push(payload.message);
      if (payload.recommended_action) lines.push('Siguiente paso: ' + payload.recommended_action);
      const sources = payload.static && payload.static.requested_by_candidates || [];
      if (sources.length) lines.push('Referencias encontradas:' + NL + ' - ' + sources.slice(0, 8).join(NL + ' - '));
      result.textContent = lines.join(NL);
    };
    window.__WADDLE_DIAG_SET_RESULT__ = renderResult;

    const updateStats = () => {
      const trace = Array.isArray(window.__WADDLE_LIVE_TRACE__) ? window.__WADDLE_LIVE_TRACE__ : [];
      const failures = trace.filter(e => e && String(e.status || '').toLowerCase() !== 'aborted' && !String(e.error || '').toUpperCase().includes('ERR_ABORTED') && (String(e.phase || '').toLowerCase() === 'error' || Number(e.statusCode || 0) >= 400 || ['unhandled-action','unhandled-context','invalid-signature','send-failed','handler-threw','network-error','http-error'].includes(String(e.status || '').toLowerCase())));
      const swfFailures = failures.filter(e => String(e.category || '').toUpperCase() === 'SWF');
      panel.querySelector('#wd-errors').textContent = String(failures.length);
      panel.querySelector('#wd-swf').textContent = String(swfFailures.length);
      panel.querySelector('#wd-events').textContent = String(trace.length);
    };
    setInterval(updateStats, 750);
    updateStats();

    toggle.addEventListener('click', () => { panel.style.display = panel.style.display === 'block' ? 'none' : 'block'; updateStats(); });
    panel.querySelector('.wd-close').addEventListener('click', () => { panel.style.display = 'none'; });
    panel.querySelector('#wd-trace').addEventListener('click', () => { result.textContent = 'Rastreando última falla...'; console.log('[WADDLE-DIAG-ACTION]trace-last'); });
    panel.querySelector('#wd-collect').addEventListener('click', () => { result.textContent = 'Recopilando consola, live trace, resolución local, runtime logs y análisis SWF...'; console.log('[WADDLE-DIAG-ACTION]collect-share'); });
    console.log('[WADDLE-DIAG][READY] Diagnostic panel installed');
    return verify();
  })()`;

  return window.webContents.executeJavaScript(script, true).then((verification: DiagnosticPanelVerification) => {
    if (!verification || !verification.toggle || !verification.panel || !verification.traceButton || !verification.collectButton || !verification.resultBridge) {
      throw new Error(`WADDLE_DIAGNOSTIC_PANEL=FAIL incomplete_dom verification=${JSON.stringify(verification)}`);
    }
    writeRuntimeDiagnostic('diagnostic-panel-ready', {
      toggle: verification.toggle,
      panel: verification.panel,
      traceButton: verification.traceButton,
      collectButton: verification.collectButton,
      resultBridge: verification.resultBridge,
      url: window.webContents.getURL()
    });
    return verification;
  }).catch(error => {
    writeRuntimeDiagnostic('diagnostic-panel-bootstrap-failed', {
      error: sanitizeDiagnosticText(error),
      url: window.webContents.getURL()
    });
    throw error;
  });
};

export const installWaddleDiagnosticPanel = (window: BrowserWindow): Promise<DiagnosticPanelVerification> => {
  let settled = false;
  let resolveReady: (value: DiagnosticPanelVerification) => void = () => undefined;
  let rejectReady: (reason?: unknown) => void = () => undefined;
  const ready = new Promise<DiagnosticPanelVerification>((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });
  const timeout = setTimeout(() => {
    if (settled) return;
    settled = true;
    rejectReady(new Error('WADDLE_DIAGNOSTIC_PANEL=FAIL readiness_timeout'));
  }, 10000);
  timeout.unref();

  window.webContents.on('did-finish-load', () => {
    void installPanelIntoRenderer(window).then(verification => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        resolveReady(verification);
      }
    }).catch(error => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        rejectReady(error);
      }
    });
  });

  window.webContents.on('console-message', (_event, level, message, line, sourceId) => {
    const text = String(message || '');
    if (text.startsWith('[WADDLE-DIAG][READY]')) return;

    if (!text.startsWith('[WADDLE-DIAG-ACTION]')) {
      recentConsoleMessages.push(sanitizeValue({ utc: new Date().toISOString(), level, message: text, line, sourceId }));
      if (recentConsoleMessages.length > consoleHistoryLimit) recentConsoleMessages.splice(0, recentConsoleMessages.length - consoleHistoryLimit);
      return;
    }

    if (text === '[WADDLE-DIAG-ACTION]trace-last') {
      void getRendererTrace(window).then(trace => {
        const failure = findLastFailure(trace);
        sendPanelResult(window, buildFailureAnalysis(failure, trace));
      }).catch(error => sendPanelResult(window, {
        schema: 'waddle-failure-analysis/v1',
        found: false,
        classification: 'ANALYSIS_FAILED',
        confidence: 'high',
        explanation: sanitizeDiagnosticText(error)
      }));
      return;
    }

    if (text === '[WADDLE-DIAG-ACTION]collect-share') {
      void collectShareBundle(window)
        .then(result => sendPanelResult(window, result))
        .catch(error => sendPanelResult(window, {
          schema: 'waddle-share-result/v1',
          ok: false,
          message: `No se pudo recopilar el diagnóstico: ${sanitizeDiagnosticText(error)}`
        }));
    }
  });

  window.on('closed', () => {
    if (settled) return;
    settled = true;
    clearTimeout(timeout);
    rejectReady(new Error('WADDLE_DIAGNOSTIC_PANEL=FAIL window_closed_before_ready'));
  });

  return ready;
};
