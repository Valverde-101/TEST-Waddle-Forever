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

export type XtActionAlias = {
  /** Exact action emitted by the archived client/runtime. */
  action: string;
  /** Canonical Waddle action that owns the authoritative implementation. */
  canonicalAction: string;
  /** Optional exact wire values used to keep special aliases narrow. */
  exactArguments?: string[];
  /** Drop wire-only selector arguments before signature parsing. */
  dropArguments?: boolean;
  /** Evidence/rationale for the alias. */
  reason: string;
};

export type ResolvedXtActionAlias = {
  action: string;
  args: string[];
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
 * Evidence-backed aliases for the preserved 2015-compatible party runtime.
 *
 * The CPImagined/Houdini runtime used by the archived party declares cookie id
 * 20150501 but emits its cookie/update requests through the historical `fair`
 * handler namespace. Waddle's reusable party implementation lives under
 * `party#...`; normalize only the proven commands instead of duplicating party
 * state logic or making XT dispatch permissive.
 *
 * `fair#fair [0]` is the odd ServerCookieService bootstrap request emitted by
 * MayPartyCookieVO.sendRequestPartyCookie(). The zero is a fixed selector, not
 * gameplay state, so it is removed before dispatch to party#partycookie.
 */
const actionAliases: XtActionAlias[] = [
  {
    action: 's%fair#fair',
    canonicalAction: 's%party#partycookie',
    exactArguments: ['0'],
    dropArguments: true,
    reason: '20150501 party runtime requests its ServerCookieVO through fair#fair with the fixed selector [0]'
  },
  {
    action: 's%fair#partycookie',
    canonicalAction: 's%party#partycookie',
    reason: 'preserved Houdini handler exposes the 20150501 party cookie under fair#partycookie'
  },
  {
    action: 's%fair#msgviewed',
    canonicalAction: 's%party#msgviewed',
    reason: 'MayPartyCookieVO emits fair#msgviewed for cookie message acknowledgement'
  },
  {
    action: 's%fair#fmsgviewed',
    canonicalAction: 's%party#msgviewed',
    reason: 'MayPartyConstants emits fair#fmsgviewed for party message acknowledgement'
  },
  {
    action: 's%fair#qcmsgviewed',
    canonicalAction: 's%party#qcmsgviewed',
    reason: 'preserved 2015 party runtime uses fair namespace for communicator acknowledgement'
  },
  {
    action: 's%fair#qtaskcomplete',
    canonicalAction: 's%party#qtaskcomplete',
    reason: 'preserved 2015 party runtime uses fair namespace for quest completion'
  },
  {
    action: 's%fair#qtupdate',
    canonicalAction: 's%party#qtupdate',
    reason: 'preserved 2015 party runtime uses fair namespace for quest coin updates'
  }
];

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

export const resolveXtActionAlias = (action: string, args: readonly string[]): ResolvedXtActionAlias | undefined => {
  const alias = actionAliases.find(candidate => {
    if (candidate.action !== action) {
      return false;
    }
    if (candidate.exactArguments === undefined) {
      return true;
    }
    return candidate.exactArguments.length === args.length && candidate.exactArguments.every((value, index) => args[index] === value);
  });

  if (alias === undefined) {
    return undefined;
  }

  return {
    action: alias.canonicalAction,
    args: alias.dropArguments ? [] : [...args],
    reason: alias.reason
  };
};

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
