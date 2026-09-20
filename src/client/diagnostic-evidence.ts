import type { WaddleLiveTraceEvent } from '@common/live-trace';

/**
 * The last HTTP 404 is often an optional client probe, not the defect the
 * player is reporting. Rank *observed* failures while retaining every noisy
 * probe in the secondary evidence. Never infer an SWF's visual contents or a
 * click's true requester from nearby network traffic.
 */
export type DiagnosticIncident = {
  signature: string;
  category: string;
  action: string;
  severity: 'critical' | 'actionable' | 'background';
  priority: number;
  occurrences: number;
  first_sequence: number;
  last_sequence: number;
  latest: WaddleLiveTraceEvent;
};

const auxiliary404 = /^(?:build\.info|game_configs\.bin)$/i;
const trailingRoute = (value: string) => {
  const noQuery = value.split(/[?#]/, 1)[0].replace(/\\/g, '/');
  try { return new URL(noQuery).pathname.toLowerCase(); } catch { return noQuery.toLowerCase(); }
};
const eventRoute = (event: WaddleLiveTraceEvent) => trailingRoute(String(event.url || event.action || ''));
const eventAction = (event: WaddleLiveTraceEvent) => String(event.action || eventRoute(event) || '').toLowerCase();

export const isDiagnosticFailure = (event: WaddleLiveTraceEvent) => {
  if (event.benign === true) return false;
  const status = String(event.status || '').toLowerCase();
  if (status === 'aborted' || String(event.error || '').toUpperCase().includes('ERR_ABORTED')) return false;
  return event.phase === 'error' || Number(event.statusCode || 0) >= 400 ||
    ['unhandled-action', 'unhandled-context', 'invalid-signature', 'send-failed',
      'handler-threw', 'network-error', 'http-error'].includes(status);
};

const priorityFor = (event: WaddleLiveTraceEvent) => {
  const code = Number(event.statusCode || 0);
  const status = String(event.status || '').toLowerCase();
  const category = event.category.toUpperCase();
  const action = eventAction(event).split('/').pop() || '';
  if (code === 404 && auxiliary404.test(action)) return { score: 10, severity: 'background' as const };
  if (category === 'FILE' && /(?:read-failed|serve-failed|missing-resolved-target|unsafe)/.test(status))
    return { score: 100, severity: 'critical' as const };
  if ((category === 'XT' || category === 'XML') &&
      ['unhandled-action', 'unhandled-context', 'handler-threw', 'send-failed'].includes(status))
    return { score: 90, severity: 'actionable' as const };
  if (category === 'SWF' && (code >= 400 || status === 'network-error'))
    return { score: 85, severity: 'actionable' as const };
  if (category === 'FILE' && event.phase === 'error')
    return { score: 78, severity: 'actionable' as const };
  if (code >= 500) return { score: 72, severity: 'actionable' as const };
  if (category === 'SWF' || category === 'XT' || category === 'XML')
    return { score: 68, severity: 'actionable' as const };
  return { score: 35, severity: 'background' as const };
};

/** Bounded, stable list of distinct failures, with occurrence counts. */
export const summarizeDiagnosticIncidents = (
  trace: WaddleLiveTraceEvent[], limit = 12
): DiagnosticIncident[] => {
  const groups = new Map<string, DiagnosticIncident>();
  for (const event of trace) {
    if (!isDiagnosticFailure(event)) continue;
    const action = eventAction(event);
    const code = Number(event.statusCode || 0);
    const status = String(event.status || (code ? 'http-' + code : 'error')).toLowerCase();
    const signature = [event.category.toUpperCase(), action, status].join('|');
    const previous = groups.get(signature);
    if (previous) {
      previous.occurrences += 1;
      previous.last_sequence = event.sequence;
      previous.latest = event;
      continue;
    }
    const { score, severity } = priorityFor(event);
    groups.set(signature, {
      signature, category: event.category.toUpperCase(), action,
      severity, priority: score, occurrences: 1,
      first_sequence: event.sequence, last_sequence: event.sequence, latest: event
    });
  }
  return [...groups.values()]
    .sort((a, b) => b.priority - a.priority || b.last_sequence - a.last_sequence)
    .slice(0, Math.max(0, limit));
};

/**
 * Relate a resource to FILE/HTTP events only when its *full path* matches;
 * matching just "map.swf" produces false attribution across party/normal maps.
 * The request ID may be reused by separate emitters: use it only together
 * with the same resource URL/route. Protocol packets remain temporal context.
 */
export const traceResourceChain = (
  failure: WaddleLiveTraceEvent, trace: WaddleLiveTraceEvent[], limit = 30
): WaddleLiveTraceEvent[] => {
  const route = eventRoute(failure);
  const id = failure.requestId;
  const at = Date.parse(failure.utc);
  return trace.filter(event => {
    if (event.sequence === failure.sequence) return true;
    if (event.category !== 'SWF' && event.category !== 'FILE' &&
        event.category !== 'OTHER' && event.category !== 'JSON' &&
        event.category !== 'XML') return false;
    const near = Number.isFinite(at) && Number.isFinite(Date.parse(event.utc)) &&
      Math.abs(Date.parse(event.utc) - at) <= 10000;
    if (!near) return false;
    const otherRoute = eventRoute(event);
    if (route && otherRoute && (route === otherRoute ||
        route.endsWith('/' + otherRoute) || otherRoute.endsWith('/' + route))) return true;
    return id !== undefined && event.requestId !== undefined &&
      String(id) === String(event.requestId) && Boolean(route && otherRoute && route === otherRoute);
  }).slice(-Math.max(1, limit));
};
