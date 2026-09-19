import { PartyProgressConfig, PartyProgressState, PartyProgressStoreData } from "@server/game-data/party";

const safePositiveInteger = (value: number | undefined): number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : 0;

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
        ...(id === 'fair-2015' ? {
          tickets: safePositiveInteger(state.tickets),
          silverTicket: safePositiveInteger(state.silverTicket),
          spinDayIndex: safePositiveInteger(state.spinDayIndex),
          fairLastSpinDay: safePositiveInteger(state.fairLastSpinDay)
        } : {})
      };
    }
  }

  private getMutable(config: PartyProgressConfig): PartyProgressState {
    const previous = this._states[config.id];
    const normalized: PartyProgressState = {
      msgViewedArray: normalizeFlags(previous?.msgViewedArray, config.messageCount),
      communicatorMsgArray: normalizeFlags(previous?.communicatorMsgArray, config.communicatorMessageCount),
      questTaskStatus: normalizeFlags(previous?.questTaskStatus, config.taskCount),
      ...(config.ticketBased ? {
        tickets: safePositiveInteger(previous?.tickets),
        silverTicket: safePositiveInteger(previous?.silverTicket),
        spinDayIndex: safePositiveInteger(previous?.spinDayIndex),
        fairLastSpinDay: safePositiveInteger(previous?.fairLastSpinDay)
      } : {})
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

  public getCookie(config: PartyProgressConfig) {
    const state = this.getMutable(config);
    return {
      msgViewedArray: [...state.msgViewedArray],
      communicatorMsgArray: [...state.communicatorMsgArray],
      questTaskStatus: [...state.questTaskStatus],
      ...(config.ticketBased ? {
        // Native Fair 2015 uses one-element arrays on the wire, while
        // Waddle persists the authoritative balances as integers.
        tickets: [state.tickets ?? 0],
        silverTicket: [state.silverTicket ?? 0],
        spinDayIndex: state.spinDayIndex ?? 0
      } : {})
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

  /** Only this party may update tickets; each mutation remains scoped to its own id. */
  public grantFairTickets(config: PartyProgressConfig, count: number): boolean {
    if (!config.ticketBased || !Number.isSafeInteger(count) || count < 0 || count > 1000) return false;
    const state = this.getMutable(config);
    const current = state.tickets ?? 0;
    if (!Number.isSafeInteger(current + count)) return false;
    state.tickets = current + count;
    return true;
  }

  public grantFairSilverTicket(config: PartyProgressConfig, count = 1): boolean {
    if (config.id !== 'fair-2015' || !config.ticketBased || !Number.isSafeInteger(count) || count <= 0 || count > 10) return false;
    const state = this.getMutable(config);
    const next = (state.silverTicket ?? 0) + count;
    if (!Number.isSafeInteger(next)) return false;
    state.silverTicket = next;
    return true;
  }

  public spendFairTickets(config: PartyProgressConfig, count: number): boolean {
    if (!config.ticketBased || !Number.isSafeInteger(count) || count <= 0) return false;
    const state = this.getMutable(config);
    if ((state.tickets ?? 0) < count) return false;
    state.tickets = (state.tickets ?? 0) - count;
    return true;
  }

  public spinFairOncePerUtcDay(config: PartyProgressConfig, utcDay: number): boolean {
    if (!config.ticketBased || !Number.isSafeInteger(utcDay) || utcDay <= 0) return false;
    const state = this.getMutable(config);
    if ((state.fairLastSpinDay ?? 0) >= utcDay) return false;
    state.fairLastSpinDay = utcDay;
    state.spinDayIndex = (state.spinDayIndex ?? 0) + 1;
    return true;
  }

  public get data(): PartyProgressStoreData {
    return Object.fromEntries(Object.entries(this._states).map(([id, state]) => [id, {
      msgViewedArray: [...state.msgViewedArray],
      communicatorMsgArray: [...state.communicatorMsgArray],
      questTaskStatus: [...state.questTaskStatus],
      ...(id === 'fair-2015' ? {
        tickets: state.tickets ?? 0,
        silverTicket: state.silverTicket ?? 0,
        spinDayIndex: state.spinDayIndex ?? 0,
        fairLastSpinDay: state.fairLastSpinDay ?? 0
      } : {})
    }]));
  }
}
