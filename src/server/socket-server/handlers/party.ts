import { publishWaddleLiveTrace } from "@common/live-trace";
import { getPartyServiceConfig } from "@server/game-data/party";
import { World } from "@server/socket-server/world/world";

import { sendError } from "./login";
import { PenguinMessenger } from "../../socket-server/messenger";
import { PenguinHandler } from "./handlers";

export const handleDonateCoins: PenguinHandler<[string, number]> = ({ prst, penguin, msg }, _, donation) => {
  // choice is useless, since we are not trying to rewrite history unfortunately

  // client doesn't check if can donate
  if (penguin.currency.coins >= donation) {
    penguin.currency.discount(donation);
  } else {
    sendError(msg, penguin, 401);
  }

  msg.send(penguin, 'dc', penguin.currency.coins);
  prst(penguin);
}

export const handleRetrieveMedieval2012: PenguinHandler<[]> = ({ penguin, msg }) => {
  const medievalMessage = penguin.medieval2012.message;
  msg.send(penguin, 'sent', JSON.stringify({
    'msgViewedArray': [medievalMessage >= 1 ? 1 : 0, medievalMessage >= 2 ? 1 : 0]
  }));
}

export const handleViewedMedieval2012: PenguinHandler<[number]> = ({ penguin, prst }, message) => {
  penguin.medieval2012.setViewed(message);
  prst(penguin);
}

export const addBakeryListener = (world: World, msg: PenguinMessenger) => {
  world.addBakeryListener(() => {
    msg.send(world.bakery.players, 'barsu', world.bakery.bakeryState);
  });
}

export const handleGetBakeryState: PenguinHandler<[]> = ({ msg, penguin, world }) => {
  msg.send(penguin, 'barsu', world.bakery.bakeryState);
}

export const handleSendEnterHopper: PenguinHandler<[string]> = ({ world }, type) => {
  // this is a recreation of this handler, it is unknown if the original handler sent the snowball type or not
  // the type was added to prevent bugs with people spamming snowballs
  // however, the way this was added isn't perfect and it's likely it didn't really check the types, as the shell function
  // never receives the snowball thrown event information, and instead I had to fetch it directly from the transformation
  // which introduces the bug of the player walking mid snowball throw
  const enumType = type.match(/\[ball(\w+)\|\d+\]/);
  if (enumType !== null) {
    const ingredient = {
      'Candy': 'Candy',
      'Egg': 'Eggs',
      'Tire': 'Tire',
      'Hay': 'Hay',
      'Flour': 'Flour',
      'Milk': 'Milk'
    }[enumType[1]];
    console.log(ingredient, world.bakery.currentIngredient, 'KKKK');
    if (world.bakery.currentIngredient === ingredient) {
      world.bakery.nextIngredient();
    }
  }
}

export const handleGetCookieInventory: PenguinHandler<[]> = ({ penguin, msg }) => {
  // placeholder just so that the animation works
  // cookie stock should theoreticailly increase when the bakery happens and decrease when a transformation happens
  // none of that is implemented however
  // and the max cookie variable is an unknown

  // current, max
  msg.send(penguin, 'ctc', 500, 1000);
}

const EMPTY_PARTY_COOKIE = {
  msgViewedArray: [],
  communicatorMsgArray: [],
  questTaskStatus: []
};

const getCurrentPartyCookie = (ctx: Parameters<PenguinHandler<[]>>[0]) => {
  const config = ctx.data.getPartyProgress();
  return config === null ? EMPTY_PARTY_COOKIE : ctx.penguin.partyProgress.getCookie(config);
};

export const sendCurrentPartyCookie: PenguinHandler<[]> = async (ctx) => {
  await ctx.msg.send(ctx.penguin, 'partycookie', JSON.stringify(getCurrentPartyCookie(ctx)));
};

const sendCurrentPartyService: PenguinHandler<[]> = async ({ penguin, msg, data }) => {
  const service = getPartyServiceConfig(data.getPartyProgress());
  if (service === undefined) {
    return;
  }

  await msg.send(penguin, 'partyservice', JSON.stringify({
    partySettings: {
      unlockDayIndex: service.unlockDayIndex,
      numOfDaysInParty: service.numOfDaysInParty
    },
    contestSettings: service.contestSettings ?? {},
    partyStartDate: service.partyStartDate,
    partyEndDate: service.partyEndDate
  }));
};

/**
 * Full modern-party bootstrap, matching the preserved Houdini/CPImagined order.
 * This helper is reusable from the join path when that path is upgraded to push
 * the whole bootstrap eagerly.
 */
export const sendModernPartyBootstrap: PenguinHandler<[]> = async (ctx) => {
  const config = ctx.data.getPartyProgress();
  if (config === null) {
    return;
  }

  const activeFeatures = ctx.data.getActiveFeatures();
  const service = getPartyServiceConfig(config);

  await ctx.msg.send(ctx.penguin, 'activefeatures', activeFeatures ?? '');
  await sendCurrentPartyCookie(ctx);
  await sendCurrentPartyService(ctx);

  publishWaddleLiveTrace({
    category: 'XT',
    phase: 'handled',
    source: 'party-bootstrap',
    action: 'modern-party-bootstrap',
    direction: 'out',
    status: service === undefined ? 'cookie-only' : 'complete',
    partyId: config.id,
    activeFeatures: activeFeatures ?? '',
    hasPartyService: service !== undefined
  });
};

/**
 * Current late-AS3 clients already request partycookie after activefeatures.
 * Return the cookie and immediately replay partyservice in the same ordered
 * handler. This closes the initialization gap even before the generic join path
 * is converted to the eager three-packet bootstrap.
 */
export const handleRetrievePartyCookie: PenguinHandler<[]> = async (ctx) => {
  await sendCurrentPartyCookie(ctx);
  await sendCurrentPartyService(ctx);

  const config = ctx.data.getPartyProgress();
  const service = getPartyServiceConfig(config);
  publishWaddleLiveTrace({
    category: 'XT',
    phase: 'handled',
    source: 'party-bootstrap',
    action: 'partycookie-partyservice',
    direction: 'out',
    status: service === undefined ? 'cookie-only' : 'complete',
    partyId: config?.id ?? '',
    activeFeatures: ctx.data.getActiveFeatures() ?? '',
    hasPartyService: service !== undefined
  });
};

export const handlePartyMessageViewed: PenguinHandler<[number]> = async (ctx, messageIndex) => {
  const { penguin, prst, data } = ctx;
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setMessageViewed(config, messageIndex)) {
    prst(penguin);
    await sendCurrentPartyCookie(ctx);
  }
};

export const handlePartyCommunicatorViewed: PenguinHandler<[number]> = async (ctx, messageIndex) => {
  const { penguin, prst, data } = ctx;
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setCommunicatorViewed(config, messageIndex)) {
    prst(penguin);
    await sendCurrentPartyCookie(ctx);
  }
};

export const handlePartyTaskComplete: PenguinHandler<[number]> = async (ctx, taskIndex) => {
  const { penguin, prst, data } = ctx;
  const config = data.getPartyProgress();
  const accepted = config !== null && penguin.partyProgress.setTaskComplete(config, taskIndex);

  if (accepted) {
    prst(penguin);
    await sendCurrentPartyCookie(ctx);
  }

  publishWaddleLiveTrace({
    category: 'XT',
    phase: 'handled',
    source: 'party-progress',
    action: 'party-task-complete',
    direction: 'in',
    status: accepted ? 'accepted' : 'rejected',
    partyId: config?.id ?? '',
    taskIndex,
    taskCount: config?.taskCount ?? 0
  });
};

/**
 * nx#bimp is late-AS3 bitmap/map telemetry, not a quest mutation packet.
 * Halloween 2015 room pickups are client-local state until the preserved
 * minigame sends party#qtaskcomplete. Never infer quest progress from bimp:
 * doing so can complete the wrong Robot Rampage task merely by leaving a room
 * through the map.
 */
export const handleModernBitmapInteraction: PenguinHandler<[string]> = async (ctx, payload) => {
  const config = ctx.data.getPartyProgress();

  publishWaddleLiveTrace({
    category: 'XT',
    phase: 'handled',
    source: 'party-bitmap-interaction',
    action: 's%nx#bimp',
    direction: 'in',
    status: 'telemetry-only',
    partyId: config?.id ?? '',
    payloadPreview: payload.slice(0, 256)
  });
};

export const handlePartyTaskUpdate: PenguinHandler<[number]> = async ({ penguin, msg, prst, data }, coins) => {
  const config = data.getPartyProgress();
  if (config === null) {
    return;
  }
  const maxCoins = Math.max(0, config.maxCoinUpdate ?? 10);
  const requested = Number.isFinite(coins) ? Math.floor(coins) : 0;
  const awarded = Math.max(0, Math.min(requested, maxCoins));
  penguin.currency.add(awarded);
  await msg.send(penguin, 'qtupdate', penguin.currency.coins);
  prst(penguin);
};
