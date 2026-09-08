export type WaddleLiveTracePhase = 'request' | 'response' | 'handled' | 'error' | 'state';

export type WaddleLiveTraceEvent = {
  schema: 'waddle-live-trace/v1';
  sequence: number;
  utc: string;
  category: string;
  phase: WaddleLiveTracePhase;
  source: string;
  action?: string;
  [key: string]: unknown;
};

export type WaddleLiveTraceInput = {
  category: string;
  phase: WaddleLiveTracePhase;
  source: string;
  action?: string;
  [key: string]: unknown;
};

type WaddleLiveTraceListener = (event: WaddleLiveTraceEvent) => void;

const listeners = new Set<WaddleLiveTraceListener>();
let sequence = 0;

export const publishWaddleLiveTrace = (input: WaddleLiveTraceInput): WaddleLiveTraceEvent => {
  const event = Object.assign({
    schema: 'waddle-live-trace/v1' as const,
    sequence: ++sequence,
    utc: new Date().toISOString()
  }, input) as WaddleLiveTraceEvent;

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
