import { SocketData } from "..";

export function handlePuffleTrick(
  this: SocketData,
  puffleId: number,
  trickId: number
) {
  const puffle = this.server.playerData.puffles.find(
    (ownedPuffle) => ownedPuffle.id === puffleId
  );

  if (puffle === undefined) {
    throw new Error(`Invalid puffle trick: puffle ${puffleId} is not owned`);
  }

  if (trickId === 0) {
    this.sendXt("pt", this.server.player.id, puffleId, 0, 0);
    return;
  }

  const TRICK_ID_MIN = 1;
  const TRICK_ID_MAX = 7;
  if (
    !Number.isInteger(trickId) ||
    trickId < TRICK_ID_MIN ||
    trickId > TRICK_ID_MAX
  ) {
    throw new Error(`Invalid puffle trick id: ${trickId}`);
  }

  const FOOD_TRICK = 3;
  const ENERGY_TRICK = 7;
  let resourceQuantity = 0;

  if (trickId === FOOD_TRICK) {
    puffle.food = Math.min(100, puffle.food + 10);
    resourceQuantity = puffle.food;
  } else if (trickId === ENERGY_TRICK) {
    puffle.health = Math.min(100, puffle.health + 10);
    resourceQuantity = puffle.health;
  }

  this.sendXt(
    "pt",
    this.server.player.id,
    puffleId,
    trickId,
    resourceQuantity
  );
}
