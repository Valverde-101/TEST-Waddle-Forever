import { PenguinHandler } from "./handlers";
import { sendCurrentPartyCookie } from "./party";
import { publishWaddleLiveTrace } from "@common/live-trace";
import { joinRoom } from "./join";

/**
 * May 2015 Fair protocol. This module has no effect on Halloween, on other
 * events or on a normal Waddle timeline: every action checks the party id.
 *
 * CPImagined's fair2015party.py documents the native command names and
 * one-element ticket arrays. Waddle persists numeric balances internally.
 */
type FairContext = Parameters<PenguinHandler<[]>>[0];
const getFairConfig = (ctx: FairContext) => {
  const config = ctx.data.getPartyProgress();
  return config?.id === "fair-2015" && config.ticketBased ? config : null;
};

const FAIR_PRIZE_COSTS: Readonly<Record<number, number>> = {
  24295: 300, 5525: 150, 24297: 300, 24298: 350, 59: 400,
  21014: 200, 21013: 200, 5523: 75, 5522: 75, 1196: 75,
  3133: 200, 148: 400, 5524: 150, 24296: 350, 91: 400,
  21011: 100, 2168: 100, 5079: 50, 328: 50, 21012: 100
};
const PUFFLE_PRIZES = new Set([59, 148, 91]);

// A client game must start before it may submit a final ticket award.
// The session is transient and scoped to the connected penguin, not to
// Halloween quests or persistent cookie flags.
const runningGames = new WeakMap<object, { gameId: number; startedAt: number }>();

const traceFair = (action: string, status: string, ctx: FairContext, detail?: number) => {
  publishWaddleLiveTrace({
    category: "XT",
    phase: "handled",
    source: "fair2015",
    action,
    direction: "in",
    status,
    partyId: ctx.data.getPartyProgress()?.id ?? "",
    ...(detail === undefined ? {} : { detail })
  });
};

export const handleFairStartGame: PenguinHandler<[number]> = async (ctx, gameId) => {
  const config = getFairConfig(ctx);
  if (config === null || !Number.isInteger(gameId) || gameId < 0 || gameId > 10000) {
    traceFair("fair#fstartgame", "rejected", ctx, gameId);
    return;
  }
  runningGames.set(ctx.penguin, { gameId, startedAt: Date.now() });
  await sendCurrentPartyCookie(ctx);
  traceFair("fair#fstartgame", "accepted", ctx, gameId);
};

export const handleFairEndGame: PenguinHandler<[number]> = async (ctx, earnedTickets) => {
  const config = getFairConfig(ctx);
  const session = runningGames.get(ctx.penguin);
  if (config === null || session === undefined ||
      Date.now() - session.startedAt > 20 * 60 * 1000 ||
      !Number.isSafeInteger(earnedTickets) || earnedTickets < 0 || earnedTickets > 1000) {
    traceFair("fair#fendgame", "rejected", ctx, earnedTickets);
    return;
  }
  runningGames.delete(ctx.penguin);
  if (!ctx.penguin.partyProgress.grantFairTickets(config, earnedTickets)) {
    traceFair("fair#fendgame", "rejected-balance", ctx, earnedTickets);
    return;
  }
  ctx.prst(ctx.penguin);
  await sendCurrentPartyCookie(ctx);
  traceFair("fair#fendgame", "awarded", ctx, earnedTickets);
};

export const handleFairAwardTicket: PenguinHandler<[number]> = async (ctx, _clientClaim) => {
  const config = getFairConfig(ctx);
  if (config === null || !ctx.penguin.partyProgress.grantFairTickets(config, 1)) {
    traceFair("fair#fawardtickets", "rejected", ctx);
    return;
  }
  ctx.prst(ctx.penguin);
  await sendCurrentPartyCookie(ctx);
  traceFair("fair#fawardtickets", "awarded", ctx, 1);
};

export const handleFairSilverJoin: PenguinHandler<[number, number, number]> = async (ctx, roomId, x, y) => {
  const config = getFairConfig(ctx);
  // MayParty.isFairRoom accepts the Fair room block 851..862. Keep this
  // protocol party-scoped so later events cannot consume Fair currency.
  if (config === null || !Number.isInteger(roomId) || roomId < 851 || roomId > 862 ||
      !Number.isInteger(x) || !Number.isInteger(y) ||
      !ctx.penguin.partyProgress.spendFairSilverTicket(config, 1)) {
    traceFair("fair#fsilverjr", "rejected", ctx, roomId);
    return;
  }

  ctx.prst(ctx.penguin);
  joinRoom(ctx, roomId, x, y);
  await sendCurrentPartyCookie(ctx);
  traceFair("fair#fsilverjr", "joined", ctx, roomId);
};

export const handleFairDailySpin: PenguinHandler<[number]> = async (ctx, _clientClaim) => {
  const config = getFairConfig(ctx);
  const utcDay = Math.floor(Date.now() / 86400000);
  if (config === null || !ctx.penguin.partyProgress.spinFairOncePerUtcDay(config, utcDay)) {
    traceFair("fair#fdailyspin", "already-spun-or-inactive", ctx);
    return;
  }

  const prize = ["TICKET", "COIN", "SPIN", "SILVER"][Math.floor(Math.random() * 4)];
  let amount = 0;
  if (prize === "TICKET") {
    const values = [75, 100, 150, 750];
    amount = values[Math.floor(Math.random() * values.length)];
    ctx.penguin.partyProgress.grantFairTickets(config, amount);
  } else if (prize === "COIN") {
    amount = Math.random() < 0.5 ? 250 : 500;
    ctx.penguin.currency.add(amount);
    await ctx.msg.send(ctx.penguin, "cdu", ctx.penguin.currency.coins, ctx.penguin.currency.coins);
  } else if (prize === "SPIN") {
    amount = 1;
    ctx.penguin.partyProgress.grantFairTickets(config, 5);
  } else {
    amount = 1;
    ctx.penguin.partyProgress.grantFairSilverTicket(config, 1);
    ctx.penguin.currency.add(1000);
    await ctx.msg.send(ctx.penguin, "cdu", ctx.penguin.currency.coins, ctx.penguin.currency.coins);
  }
  await ctx.msg.send(ctx.penguin, "fdailyspin", prize, amount, amount);
  ctx.prst(ctx.penguin);
  await sendCurrentPartyCookie(ctx);
  traceFair("fair#fdailyspin", "awarded-" + prize.toLowerCase(), ctx, amount);
};

export const handleFairUseTickets: PenguinHandler<[number]> = async (ctx, itemId) => {
  const config = getFairConfig(ctx);
  const cost = FAIR_PRIZE_COSTS[itemId];
  const pufflePrize = PUFFLE_PRIZES.has(itemId);
  const item = pufflePrize ? undefined : ctx.data.getItem(itemId);
  if (config === null || cost === undefined || (item === undefined && !pufflePrize) ||
      (!pufflePrize && ctx.penguin.inventory.has(itemId)) ||
      !ctx.penguin.partyProgress.spendFairTickets(config, cost)) {
    traceFair("fair#fusetickets", "rejected", ctx, itemId);
    return;
  }
  if (pufflePrize) {
    const owned = ctx.penguin.puffle.addItem(itemId, 1);
    await ctx.msg.send(ctx.penguin, "papi", ctx.penguin.currency.coins, itemId, owned);
  } else {
    ctx.penguin.inventory.add(itemId);
    await ctx.msg.send(ctx.penguin, "ai", itemId, ctx.penguin.currency.coins);
  }
  ctx.prst(ctx.penguin);
  await sendCurrentPartyCookie(ctx);
  traceFair("fair#fusetickets", "purchased", ctx, itemId);
};
