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
        questTaskStatus: [...(state.questTaskStatus ?? [])]
      };
    }
  }

  private getMutable(config: PartyProgressConfig): PartyProgressState {
    const previous = this._states[config.id];
    const normalized: PartyProgressState = {
      msgViewedArray: normalizeFlags(previous?.msgViewedArray, config.messageCount),
      communicatorMsgArray: normalizeFlags(previous?.communicatorMsgArray, config.communicatorMessageCount),
      questTaskStatus: normalizeFlags(previous?.questTaskStatus, config.taskCount)
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

  public get data(): PartyProgressStoreData {
    return Object.fromEntries(Object.entries(this._states).map(([id, state]) => [id, {
      msgViewedArray: [...state.msgViewedArray],
      communicatorMsgArray: [...state.communicatorMsgArray],
      questTaskStatus: [...state.questTaskStatus]
    }]));
  }
}
