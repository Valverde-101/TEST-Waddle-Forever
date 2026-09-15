export type PartyServiceConfig = {
  /** Date string passed verbatim to the late-AS3 party runtime. */
  partyStartDate: string;
  /** Date string passed verbatim to the late-AS3 party runtime. */
  partyEndDate: string;
  /** Day made available to the party UI/quest runtime. */
  unlockDayIndex: number;
  /** Total number of days exposed to the party runtime. */
  numOfDaysInParty: number;
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
   * party configuration avoids adding Halloween-specific state to GameData and
   * makes the same bootstrap reusable for later modern parties.
   */
  service?: PartyServiceConfig;
};

export type PartyProgressState = {
  msgViewedArray: number[];
  communicatorMsgArray: number[];
  questTaskStatus: number[];
};

export type PartyProgressStoreData = Record<string, PartyProgressState>;
