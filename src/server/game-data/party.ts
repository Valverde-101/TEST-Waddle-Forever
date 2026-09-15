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
};

/**
 * Server-side configuration consumed by the late-AS3 BaseParty runtime through
 * the `partyservice` XT response. Keep this generic: individual parties provide
 * their dates/day settings while the socket bootstrap remains reusable.
 */
export type PartyServiceConfig = {
  partyStartDate: string;
  partyEndDate: string;
  unlockDayIndex: number;
  numOfDaysInParty: number;
};

export type PartyProgressState = {
  msgViewedArray: number[];
  communicatorMsgArray: number[];
  questTaskStatus: number[];
};

export type PartyProgressStoreData = Record<string, PartyProgressState>;
