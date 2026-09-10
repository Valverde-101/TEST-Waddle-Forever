import { PenguinMessenger } from "../messenger";
import { WorldPenguin } from "../world/world-penguin";
import { PenguinHandler, RoomContext, RoomHandler } from "./handlers";
import { handlePuffleDigOnCommand, handlePuffleDigRandom } from "./puffle";

const PUFFLE_DIG_COOLDOWN_SECONDS = 120;
const lastSuccessfulDig = new WeakMap<WorldPenguin, number>();

/**
 * Tracks the Vanilla puffle-dig cooldown at the protocol boundary.
 *
 * The existing Waddle dig implementation has several successful reward paths
 * and a `nodig` path. Rather than duplicating or changing that gameplay logic,
 * we observe the authoritative outgoing `puffledig` packet: it is emitted only
 * after a successful dig. This matches Houdini's Vanilla contract, where the
 * 120-second timestamp is updated on a successful dig and `getdigcooldown`
 * returns the remaining whole seconds (or zero).
 */
const withSuccessfulDigTracking = (handler: RoomHandler<[]>): RoomHandler<[]> => {
  return (ctx) => {
    const trackedMessenger = Object.create(ctx.msg) as PenguinMessenger;
    trackedMessenger.send = (penguins, message, ...args) => {
      if (message === 'puffledig') {
        lastSuccessfulDig.set(ctx.penguin, Date.now());
      }
      return ctx.msg.send(penguins, message, ...args);
    };

    const trackedContext: RoomContext = { ...ctx, msg: trackedMessenger };
    return handler(trackedContext);
  };
};

export const handlePuffleDigRandomWithCooldown = withSuccessfulDigTracking(handlePuffleDigRandom);
export const handlePuffleDigOnCommandWithCooldown = withSuccessfulDigTracking(handlePuffleDigOnCommand);

export const handleGetPuffleDigCooldown: PenguinHandler<[]> = ({ msg, penguin }) => {
  const lastDig = lastSuccessfulDig.get(penguin);
  if (lastDig === undefined) {
    msg.send(penguin, 'getdigcooldown', 0);
    return;
  }

  const elapsedSeconds = Math.floor((Date.now() - lastDig) / 1000);
  const remainingSeconds = Math.max(0, PUFFLE_DIG_COOLDOWN_SECONDS - elapsedSeconds);
  if (remainingSeconds === 0) {
    lastSuccessfulDig.delete(penguin);
  }
  msg.send(penguin, 'getdigcooldown', remainingSeconds);
};
