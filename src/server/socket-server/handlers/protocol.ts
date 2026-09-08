export type XtCompatibilityRule = {
  /** Exact extension/action pair produced by parseXtMessage, e.g. s%g#gili. */
  action: string;
  /** Number of client arguments accepted by this compatibility rule. */
  argumentCount: number;
  /** Why accepting the variant is safe for the offline server. */
  reason: string;
};

/**
 * Client-to-server packets that are acknowledgements/lifecycle notifications,
 * not gameplay commands. They are intentionally accepted without a response.
 *
 * j#crl: client room SWF finished loading. Historical CPPS implementations
 * handled this as an empty room-loaded callback.
 *
 * bi#ack: Airtower acknowledgement for selected server commands. The payload is
 * variable-length telemetry metadata (time=<epoch>, acknowledged command, ...).
 */
const noResponseClientPackets = new Set<string>([
  's%j#crl',
  's%bi#ack'
]);

/**
 * Explicit compatibility aliases for read-only requests whose modern client
 * variants append metadata that older Waddle handlers do not consume.
 *
 * These rules are deliberately narrow: an unsupported action still fails as an
 * unhandled XT, and an unexpected argument count still fails signature parsing.
 * This avoids turning protocol drift into a blanket "accept anything" policy.
 */
const compatibilityRules: XtCompatibilityRule[] = [
  {
    action: 's%g#gili',
    argumentCount: 2,
    reason: 'modern igloo-like pagination adds start/end while the offline response currently contains no persisted liker list'
  },
  {
    action: 's%g#ggd',
    argumentCount: 2,
    reason: 'modern game-data requests append client metadata; the legacy read-only Waddle handler does not consume request arguments'
  }
];

export const isNoResponseClientPacket = (action: string): boolean => noResponseClientPackets.has(action);

export const getXtCompatibilityRule = (action: string, argumentCount: number): XtCompatibilityRule | undefined => {
  return compatibilityRules.find(rule => rule.action === action && rule.argumentCount === argumentCount);
};
