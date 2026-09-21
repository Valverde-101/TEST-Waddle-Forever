export type PartyServiceConfig = {
  /** Date string passed verbatim to the late-AS3 party runtime. */
  partyStartDate: string;
  /** Date string passed verbatim to the late-AS3 party runtime. */
  partyEndDate: string;
  /** Day made available to the party UI/quest runtime. */
  unlockDayIndex: number;
  /** Total number of days exposed to the party runtime. */
  numOfDaysInParty: number;
  /** Optional late-AS3 contest metadata. Empty object keeps templated runtimes safe. */
  contestSettings?: Record<string, unknown>;
};

export type PartyProgressConfig = {
  /** Stable key used to persist this party independently from other parties. */
  id: string;
  /** Number of normal party messages tracked by msgviewed. */
  messageCount: number;
  /** Number of communicator messages tracked by qcmsgviewed. */
  communicatorMessageCount: number;
  /** Number of quest/task slots tracked by qtaskcomplete. */
  taskCount: number;
  /** Maximum coins accepted in one qtupdate packet. Defaults to 10. */
  maxCoinUpdate?: number;
  /**
   * Optional late-AS3 `partyservice` bootstrap. Keeping this with the persisted
   * party configuration makes the runtime reusable for later modern parties.
   */
  service?: PartyServiceConfig;
};

/**
 * Evidence-backed service metadata for archived parties whose initial Waddle
 * timeline definition predates the generic `service` field. New integrations
 * should declare `service` directly in PartyProgressConfig; this table is only a
 * compatibility bridge for already-landed party data.
 */
const ARCHIVED_PARTY_SERVICES: Readonly<Record<string, PartyServiceConfig>> = {
  'halloween-2015': {
    partyStartDate: '2015-10-21 00:00:00',
    partyEndDate: '2015-11-05 00:00:00',
    unlockDayIndex: 16,
    numOfDaysInParty: 16,
    contestSettings: {}
  }
};

export const getPartyServiceConfig = (config: PartyProgressConfig | null): PartyServiceConfig | undefined => {
  if (config === null) {
    return undefined;
  }
  return config.service ?? ARCHIVED_PARTY_SERVICES[config.id];
};

export type PartyProgressState = {
  /** Offline-only cumulative Coins for Change donations; not in the partycookie payload. */
  donatedCoins?: number;
  msgViewedArray: number[];
  communicatorMsgArray: number[];
  questTaskStatus: number[];
};

export type PartyProgressStoreData = Record<string, PartyProgressState>;
