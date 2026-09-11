import { RoomHandler } from "./handlers";

/**
 * Broadcasts a vanilla puffle trick request to the current room.
 *
 * The server does not select or load the trick SWF. The Flash client receives
 * `puffletrick`, combines the walking puffle metadata with the trick id and
 * resolves the sprite through its `w.puffle.sprite.tricks` path mapping.
 */
export const handlePuffleTrick: RoomHandler<[number]> = ({ msg, penguin, room }, trickId) => {
  if (penguin.puffle.getWalking() === undefined) {
    return;
  }

  msg.send(room.players, 'puffletrick', penguin.id, trickId);
};
