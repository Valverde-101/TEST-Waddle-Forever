export type WaddleLiveTracePhase = 'request' | 'response' | 'handled' | 'error' | 'state';

export type WaddleLiveTraceDirection = 'in' | 'out';

/**
 * Common fields shared by browser-resource, file-server, XT and XML telemetry.
 * Producers may still add domain-specific metadata through the index signature,
 * but keeping the common contract here prevents each diagnostic consumer from
 * reinventing the same loose shape.
 */
export type WaddleLiveTraceData = {
  category: string;
  phase: WaddleLiveTracePhase;
  source: string;
  action?: string;
  status?: string;
  statusCode?: number;
  requestId?: number | string;
  method?: string;
  url?: string;
  direction?: WaddleLiveTraceDirection;
  durationMs?: number | null;
  fromCache?: boolean;
  error?: string;
  reason?: string;
  resolver?: string;
  target?: string;
  assetKind?: string;
  [key: string]: unknown;
};

export type WaddleLiveTraceEvent = WaddleLiveTraceData & {
  schema: 'waddle-live-trace/v1';
  sequence: number;
  utc: string;
};

export type WaddleLiveTraceInput = WaddleLiveTraceData;

type WaddleLiveTraceListener = (event: WaddleLiveTraceEvent) => void;

const listeners = new Set<WaddleLiveTraceListener>();
let sequence = 0;

const sensitiveTraceKey = /^(?:pass|password|passwd|token|authorization|auth|session|secret|cookie|api[_-]?key|body|payload)$/i;
const structuredBodyKey = /^(?:request|response|raw|message)(?:body|payload)$/i;
const delimitedBodyKey = /(?:^|[_-])(?:body|payload)$/i;
const sensitiveQueryKey = /^(?:pass|password|passwd|token|authorization|auth|session|secret|key|api[_-]?key)$/i;
const unsafeObjectKey = /^(?:__proto__|prototype|constructor)$/;
const maxTraceStringLength = 4096;
const maxTraceArrayLength = 200;
const maxTraceDepth = 8;

const isSensitiveTraceKey = (keyName: string) => (
  sensitiveTraceKey.test(keyName) || structuredBodyKey.test(keyName) || delimitedBodyKey.test(keyName)
);

const sanitizeTraceString = (value: string) => {
  let text = value;
  text = text.replace(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi, 'Bearer [redacted]');
  text = text.replace(/((?:password|passwd|token|authorization|auth|session|secret|api[_-]?key|cookie)\s*[=:]\s*)([^\s&;"']+)/gi, '$1[redacted]');

  // A large part of live telemetry is URL-shaped. Redact sensitive query values
  // centrally so a new producer cannot accidentally bypass a caller-local URL
  // sanitizer. If it is not a valid absolute URL, keep the already-scrubbed text.
  try {
    const parsed = new URL(text);
    parsed.username = '';
    parsed.password = '';
    for (const key of Array.from(parsed.searchParams.keys())) {
      if (sensitiveQueryKey.test(key)) parsed.searchParams.set(key, '[redacted]');
    }
    text = parsed.toString();
  } catch {
    // Not all trace strings are URLs.
  }

  return text.length <= maxTraceStringLength
    ? text
    : `${text.slice(0, maxTraceStringLength)}...[truncated]`;
};

const sanitizeTraceValue = (
  value: unknown,
  keyName = '',
  depth = 0,
  seen: WeakSet<object> = new WeakSet<object>()
): unknown => {
  if (isSensitiveTraceKey(keyName)) return '[redacted]';
  if (value === null || value === undefined || typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'string') return sanitizeTraceString(value);
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'function' || typeof value === 'symbol') return `[${typeof value}]`;
  if (depth >= maxTraceDepth) return '[max-depth]';

  if (typeof value === 'object') {
    if (seen.has(value)) return '[circular]';
    seen.add(value);

    if (Array.isArray(value)) {
      return value.slice(0, maxTraceArrayLength).map(item => sanitizeTraceValue(item, '', depth + 1, seen));
    }

    // A null-prototype object prevents special keys from changing the prototype
    // while sanitizing untrusted diagnostic metadata. Dangerous object-shape keys
    // are omitted entirely because they have no legitimate tracing purpose.
    const output = Object.create(null) as Record<string, unknown>;
    for (const [key, child] of Object.entries(value)) {
      if (unsafeObjectKey.test(key)) continue;
      output[key] = sanitizeTraceValue(child, key, depth + 1, seen);
    }
    return output;
  }

  return sanitizeTraceString(String(value));
};

const sanitizeTraceInput = (input: WaddleLiveTraceInput): WaddleLiveTraceInput => {
  return sanitizeTraceValue(input) as WaddleLiveTraceInput;
};

export const publishWaddleLiveTrace = (input: WaddleLiveTraceInput): WaddleLiveTraceEvent => {
  const safeInput = sanitizeTraceInput(input);

  // The producer controls diagnostic metadata, never the envelope. Put the
  // authoritative fields last so even a buggy producer passing schema/sequence/utc
  // through the open metadata signature cannot forge ordering or schema identity.
  const event = {
    ...safeInput,
    schema: 'waddle-live-trace/v1' as const,
    sequence: ++sequence,
    utc: new Date().toISOString()
  } as WaddleLiveTraceEvent;

  for (const listener of listeners) {
    try {
      listener(event);
    } catch {
      // Live tracing must never alter game behavior. The persistent runtime
      // diagnostics layer records its own failures independently.
    }
  }

  return event;
};

export const subscribeWaddleLiveTrace = (listener: WaddleLiveTraceListener) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
};
