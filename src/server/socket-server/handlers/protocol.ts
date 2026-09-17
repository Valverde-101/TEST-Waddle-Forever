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
  /** Why accepting the variant is safe for the offline server. */
  reason: string;
};

/**
 * Client-to-server packets that are acknowledgements/lifecycle/telemetry
 * notifications, not gameplay commands. They are intentionally accepted without
 * a response.
 *
 * j#crl: client room SWF finished loading. Historical CPPS implementations
 * handled this as an empty room-loaded callback.
 *
 * bi#ack: Airtower acknowledgement for selected server commands. The payload is
 * variable-length telemetry metadata (time=<epoch>, acknowledged command, ...).
 *
 * nx#bimp: late-AS3 map impression payload. Live Trace consistently shows one
 * opaque string immediately after map.swf opens, followed directly by j#jr; the
 * client does not wait for or consume a server response. Treating it as telemetry
 * removes a false protocol error without fabricating map/gameplay state.
 *
 * p#bipa / p#bipc: late-AS3 puffle adoption/care BI packets. Preserved
 * BridgeFilter code identifies them as telemetry events, while the gameplay
 * mutation is handled by the p#pn adoption and puffle inventory/care packets.
 */
const noResponseClientPackets = new Set<string>([
  's%j#crl',
  's%bi#ack',
  's%nx#bimp',
  's%p#bipa',
  's%p#bipc'
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
 * Narrow vanilla read-only fallbacks proven against preserved server contracts.
 *
 * p#getdigcooldown returns seconds remaining until another puffle treasure dig.
 * Waddle does not persist a treasure-dig cooldown, so zero is the truthful
 * compatibility value.
 *
 * f#epfgm retrieves EPF communication messages. Waddle has no EPF COM-message
 * store, so the canonical empty response is unread=0 with no message payload.
 *
 * i#currencies is the late-AS3 currency-balance query. Preserved Houdini sends
 * `currencies` with pipe-delimited pairs such as `1|<gold nuggets>`. Waddle has
 * no persisted golden-nugget balance, so `1|0` is the truthful empty state.
 *
 * musictrack#broadcastingmusictracks asks SoundStudio for the live shared-track
 * playlist. Solero/Houdini's vanilla contract returns (0, -1, "") when no shared
 * playlist exists. Waddle has no persisted SoundStudio broadcast queue, so that
 * exact empty state is truthful and prevents room entry from becoming an
 * unhandled protocol error.
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
  },
  {
    action: 's%i#currencies',
    responseAction: 'currencies',
    responseArgs: ['1|0'],
    reason: 'late-AS3 currency balance query; preserved server contract encodes golden nuggets as currency 1 and Waddle has no persisted nugget balance'
  },
  {
    action: 's%musictrack#broadcastingmusictracks',
    responseAction: 'broadcastingmusictracks',
    responseArgs: [0, -1, ''],
    reason: 'vanilla SoundStudio broadcast query; offline Waddle has no shared live playlist, matching the canonical empty playlist response'
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
