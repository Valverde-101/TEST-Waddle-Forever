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

export type PartyProgressState = {
  msgViewedArray: number[];
  communicatorMsgArray: number[];
  questTaskStatus: number[];
};

export type PartyProgressStoreData = Record<string, PartyProgressState>;
