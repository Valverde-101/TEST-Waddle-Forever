import { PenguinHandler } from './handlers';

/**
 * Modern shells send j#crl after the room SWF has finished loading. The legacy
 * server does not need to mutate state or answer this acknowledgement; handling
 * it explicitly prevents a valid lifecycle packet from being classified as an
 * unsupported gameplay action.
 */
export const handleClientRoomLoaded: PenguinHandler<[]> = () => undefined;

/**
 * Airtower sends bi#ack after selected server commands (for example room/world
 * transitions). The payload is telemetry/ack metadata such as time=<epoch> and
 * the acknowledged command. It is intentionally variable-length and requires
 * no response in the offline server.
 */
export const handleClientCommandAck: PenguinHandler<string[]> = () => undefined;
