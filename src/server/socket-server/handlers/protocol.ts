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

export const isNoResponseClientPacket = (action: string): boolean => noResponseClientPackets.has(action);
