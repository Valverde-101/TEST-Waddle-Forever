import { PartyProgressConfig, PartyProgressState, PartyProgressStoreData } from "@server/game-data/party";

const normalizeFlags = (values: number[] | undefined, length: number): number[] => {
  const safeLength = Math.max(0, Math.floor(length));
  return Array.from({ length: safeLength }, (_, index) => values?.[index] === 1 ? 1 : 0);
};

/**
 * Persistent storage for modern party progress packets.
 *
 * The protocol is shared by multiple parties (`partycookie`, `msgviewed`,
 * `qcmsgviewed`, `qtaskcomplete`, `qtupdate`). Party-specific code only
 * supplies a PartyProgressConfig; this class keeps each party isolated by id.
 */
export class PartyProgressStore {
  private _states: PartyProgressStoreData;

  constructor(data?: PartyProgressStoreData) {
    this._states = {};
    for (const [id, state] of Object.entries(data ?? {})) {
      this._states[id] = {
        msgViewedArray: [...(state.msgViewedArray ?? [])],
        communicatorMsgArray: [...(state.communicatorMsgArray ?? [])],
        questTaskStatus: [...(state.questTaskStatus ?? [])],
        donatedCoins: Number.isSafeInteger(state.donatedCoins) && (state.donatedCoins ?? 0) >= 0 ? state.donatedCoins : 0
      };
    }
  }

  private getMutable(config: PartyProgressConfig): PartyProgressState {
    const previous = this._states[config.id];
    const normalized: PartyProgressState = {
      msgViewedArray: normalizeFlags(previous?.msgViewedArray, config.messageCount),
      communicatorMsgArray: normalizeFlags(previous?.communicatorMsgArray, config.communicatorMessageCount),
      questTaskStatus: normalizeFlags(previous?.questTaskStatus, config.taskCount),
      donatedCoins: previous?.donatedCoins ?? 0
    };
    this._states[config.id] = normalized;
    return normalized;
  }

  private setFlag(values: number[], index: number): boolean {
    if (!Number.isInteger(index) || index < 0 || index >= values.length) {
      return false;
    }
    values[index] = 1;
    return true;
  }

  public getCookie(config: PartyProgressConfig): PartyProgressState {
    const state = this.getMutable(config);
    return {
      msgViewedArray: [...state.msgViewedArray],
      communicatorMsgArray: [...state.communicatorMsgArray],
      questTaskStatus: [...state.questTaskStatus]
    };
  }

  public setMessageViewed(config: PartyProgressConfig, index: number): boolean {
    return this.setFlag(this.getMutable(config).msgViewedArray, index);
  }

  public setCommunicatorViewed(config: PartyProgressConfig, index: number): boolean {
    return this.setFlag(this.getMutable(config).communicatorMsgArray, index);
  }

  public setTaskComplete(config: PartyProgressConfig, index: number): boolean {
    return this.setFlag(this.getMutable(config).questTaskStatus, index);
  }

  /** Persisted per-penguin offline total. Never present it as the historical global total. */
  public getDonatedCoins(config: PartyProgressConfig): number {
    return this.getMutable(config).donatedCoins ?? 0;
  }

  public addDonation(config: PartyProgressConfig, amount: number): number {
    if (config.id !== 'holiday-2015' || !Number.isSafeInteger(amount) || amount <= 0) {
      return this.getDonatedCoins(config);
    }
    const state = this.getMutable(config);
    state.donatedCoins = Math.min(Number.MAX_SAFE_INTEGER, (state.donatedCoins ?? 0) + amount);
    return state.donatedCoins;
  }

  public get data(): PartyProgressStoreData {
    return Object.fromEntries(Object.entries(this._states).map(([id, state]) => [id, {
      msgViewedArray: [...state.msgViewedArray],
      communicatorMsgArray: [...state.communicatorMsgArray],
      questTaskStatus: [...state.questTaskStatus],
      donatedCoins: state.donatedCoins ?? 0
    }]));
  }
}
