import { PenguinHandler, RoomHandler } from "./handlers";

/**
 * Vanilla-client protocol handlers whose contracts are independently confirmed
 * against the client's observed XT shape and Houdini's long-lived cross-era
 * implementation. Keep this file deliberately narrow: unknown packets must stay
 * unhandled until their contract is proven rather than being silently accepted.
 */

/**
 * u#followpath(path)
 *
 * The client sends one numeric path identifier. The server does not mutate the
 * penguin's x/y state here; it broadcasts the path so every client in the room
 * can run the same path animation. This mirrors the canonical room broadcasts
 * used by u#sp/u#sf in Waddle.
 */
export const handleFollowPath: RoomHandler<[number]> = ({ penguin, room, msg }, path) => {
  msg.send(room.players, 'followpath', penguin.id, path);
};

/**
 * g#pio(penguinId) — "player igloo open".
 *
 * Waddle already owns the authoritative open-igloo set in World, so answer from
 * that state instead of inventing a second compatibility cache.
 */
export const handleIsPlayerIglooOpen: PenguinHandler<[number]> = ({ penguin, world, msg }, penguinId) => {
  const isOpen = world.getOpenIglooPlayers().some(openPenguin => openPenguin.id === penguinId);
  msg.send(penguin, 'pio', isOpen ? 1 : 0);
};

/**
 * u#gabcms — legacy/vanilla A/B-test probe.
 *
 * The reference server intentionally performs no work and sends no response.
 * Registering it explicitly distinguishes a known no-op protocol request from
 * a genuinely unsupported XT action without weakening the global XT handler.
 */
export const handleGetAbTestData: PenguinHandler<[]> = () => {
  // Intentionally empty.
};
