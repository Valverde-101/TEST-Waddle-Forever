export type XtCompatibilityRule = {
  /** Exact extension/action pair produced by parseXtMessage, e.g. s%g#gili. */
  action: string;
  /** Number of client arguments accepted by this compatibility rule. */
  argumentCount: number;
  /** Optional exact wire values. Use this for protocol variants whose payload is a fixed selector/version token. */
  exactArguments?: string[];
  /** Why accepting the variant is safe for the offline server. */
  reason: string;
};

export type XtReadOnlyFallback = {
  /** Exact client action. */
  action: string;
  /** XT action returned to the vanilla client. */
  responseAction: string;
  /** Static arguments used only when Waddle has no persisted subsystem state. */
  responseArgs: Array<string | number>;
  /** Evidence/rationale for the compatibility response. */
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
 * Explicit compatibility aliases for client protocol variants whose extra/missing
 * request fields do not change the authoritative state returned by Waddle.
 *
 * Keep these narrow. In particular, fixed selector/version fields should use
 * exactArguments so a real historical packet is accepted without turning the XT
 * parser into a permissive catch-all.
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
  },
  {
    action: 's%l#mg',
    argumentCount: 0,
    reason: 'late-AS3 mail clients request the inbox without the legacy pagination/count argument; the Waddle mail read handler does not require request metadata'
  },
  {
    action: 's%g#gii',
    argumentCount: 1,
    reason: 'late-AS3 igloo inventory queries include a player/owner selector while Waddle resolves the current offline player context server-side'
  },
  {
    action: 's%party#partycookie',
    argumentCount: 1,
    exactArguments: ['0'],
    reason: '2015 ServerCookieService requests the generic party cookie with the fixed selector [0]; the active timeline already selects the persisted party state'
  }
];

/**
 * Narrow vanilla read-only fallbacks proven against Solero/Houdini contracts.
 *
 * p#getdigcooldown returns seconds remaining until another puffle treasure dig.
 * Waddle does not persist a treasure-dig cooldown, so zero is the truthful
 * compatibility value.
 *
 * f#epfgm retrieves EPF communication messages. Waddle has no EPF COM-message
 * store, so the canonical empty response is unread=0 with no message payload.
 *
 * Keep these exact and response-bearing. They must not be converted into the
 * no-response acknowledgement set because the vanilla client waits for them.
 */
const readOnlyFallbacks: XtReadOnlyFallback[] = [
  {
    action: 's%p#getdigcooldown',
    responseAction: 'getdigcooldown',
    responseArgs: [0],
    reason: 'vanilla puffle dig cooldown query; offline Waddle has no persisted cooldown state'
  },
  {
    action: 's%f#epfgm',
    responseAction: 'epfgm',
    responseArgs: [0],
    reason: 'vanilla EPF COM-message query; offline Waddle has no COM-message store'
  }
];

export const isNoResponseClientPacket = (action: string): boolean => noResponseClientPackets.has(action);

export const getXtCompatibilityRule = (action: string, args: readonly string[]): XtCompatibilityRule | undefined => {
  return compatibilityRules.find(rule => {
    if (rule.action !== action || rule.argumentCount !== args.length) {
      return false;
    }
    if (rule.exactArguments === undefined) {
      return true;
    }
    return rule.exactArguments.length === args.length && rule.exactArguments.every((value, index) => args[index] === value);
  });
};

export const getXtReadOnlyFallback = (action: string): XtReadOnlyFallback | undefined => {
  return readOnlyFallbacks.find(rule => rule.action === action);
};
