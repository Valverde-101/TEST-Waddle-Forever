import { ArgumentsIndicator, parseArgs } from "@server/socket-server/arg-parser";
import { ClientSocket } from "./socket-server";
import { WorldContext } from "@server/socket-server/handlers/handlers";
import { getBlueString, getRedString, logverbose } from "@server/logger";
import { publishWaddleLiveTrace } from "@common/live-trace";
import { getXtCompatibilityRule, getXtReadOnlyFallback, isNoResponseClientPacket } from "./handlers/protocol";

type ParsedXtMessage = {
  name: string;
  args: string[];
};

type XtParseResult =
  | { ok: true; value: ParsedXtMessage }
  | { ok: false; reason: string };

/**
 * Native late-2015 party SWFs span three proven XT namespaces for the same
 * cookie/progress state:
 * - `party`: generic modern quest handlers;
 * - `halloween`: event-specific preserved variants;
 * - `fair`: the MayParty/20150501 bootstrap reused by Halloween 2015.
 *
 * Canonicalize only commands evidenced by the preserved clients. In particular,
 * MayPartyCookieVO requests its first cookie as `fair#fair` with selector [0].
 * Do not make arbitrary `fair#*` traffic valid: the unrelated Fair ticket/game
 * command family remains outside this compatibility map.
 */
const XT_ACTION_ALIASES = new Map<string, string>([
  ['s%halloween#partycookie', 's%party#partycookie'],
  ['s%halloween#msgviewed', 's%party#msgviewed'],
  ['s%halloween#qcmsgviewed', 's%party#qcmsgviewed'],
  ['s%halloween#qtaskcomplete', 's%party#qtaskcomplete'],
  ['s%halloween#qtupdate', 's%party#qtupdate'],
  // MayPartyCookieVO.PARTY_COOKIE_ID = 20150501 and
  // MAY_COOKIE_HANDLER_NAME = "fair". Its static cookie request serializes
  // `(fair#fair, [0])`; some preserved server packs use fair#partycookie.
  ['s%fair#fair', 's%party#partycookie'],
  ['s%fair#partycookie', 's%party#partycookie'],
  ['s%fair#msgviewed', 's%party#msgviewed']
]);

const canonicalizeXtAction = (action: string): string => XT_ACTION_ALIASES.get(action) ?? action;

const parseXtMessage = (message: string): XtParseResult => {
  if (!message.startsWith('%xt%')) {
    return { ok: false, reason: 'missing-xt-prefix' };
  }
  if (!message.endsWith('%')) {
    return { ok: false, reason: 'missing-frame-terminator' };
  }

  const values = message.split('%');
  if (values.length < 6 || values[0] !== '' || values[1] !== 'xt' || values[values.length - 1] !== '') {
    return { ok: false, reason: 'invalid-frame-shape' };
  }

  const extension = values[2];
  const code = values[3];
  if (extension.length === 0 || code.length === 0) {
    return { ok: false, reason: 'missing-action' };
  }

  return {
    ok: true,
    value: {
      name: `${extension}%${code}`,
      // values[4] is the room/internal request id and is intentionally handled by
      // the protocol layer rather than passed to individual gameplay handlers.
      args: values.slice(5, values.length - 1)
    }
  };
};

type CtxGuard<Ctx extends WorldContext> = [(ctx: WorldContext) => ctx is Ctx,
  (ctx: Ctx) => boolean];

export type XtCallbackInfo<Ctx extends WorldContext> = [
  CtxGuard<Ctx>,
  ArgumentsIndicator,
  (ctx: Ctx, ...args: Array<string | number>) => void | Promise<void>,
  XtParams
];

type XtCallbackInfoWrapped<Ctx extends WorldContext> = [
  CtxGuard<Ctx>,
  ArgumentsIndicator,
  CallbackManager<Ctx>
];

export type XtParams = {
  once?: boolean
  /** In milliseconds, how much to wait before accepting the next packet. */
  cooldown?: number
}

class CallbackManager<Ctx extends WorldContext> {
  private _cooldown: number | null = null;
  private _once = false;
  private _handled = new WeakMap<ClientSocket, boolean>();
  private _timestamps = new WeakMap<ClientSocket, number>();

  constructor(private _callback: (ctx: Ctx, ...args: Array<string | number>) => Promise<void> | void, params?: XtParams) {
    if (params?.cooldown !== undefined) {
      this._cooldown = params.cooldown;
    }
    if (params?.once !== undefined) {
      this._once = params.once;
    }
  }

  call(client: ClientSocket, ctx: Ctx, action: string, ...args: Array<string | number>) {
    const now = Date.now();

    if (this._cooldown !== null) {
      const last = this._timestamps.get(client);
      if (last !== undefined && last + this._cooldown > now) {
        const remainingMs = Math.max(0, last + this._cooldown - now);
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'handled',
          source: 'xt-handler',
          action,
          status: 'rate-limited',
          argCount: args.length,
          cooldownMs: this._cooldown,
          remainingMs
        });
        return;
      }
    }

    if (this._once && this._handled.get(client)) {
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'handled',
        source: 'xt-handler',
        action,
        status: 'already-handled',
        argCount: args.length
      });
      return;
    }

    if (this._cooldown !== null) {
      this._timestamps.set(client, now);
    }
    if (this._once) {
      this._handled.set(client, true);
    }

    return this._callback(ctx, ...args);
  }
}

export class XtHandler {
  private _callbacks: Map<string, XtCallbackInfoWrapped<any>[]>;

  constructor(callbacks: Array<[string, XtCallbackInfo<any>[]]>, private _disconnect: (ctx: WorldContext) => Promise<void>) {
    this._callbacks = new Map(
      callbacks.map(
        ([key, value]) => [key, value.map(
          ([pair, args, callback, params]) => [pair, args, new CallbackManager(callback, params)]
        )]
      )
    );
  }

  public handle(client: ClientSocket, context: WorldContext, message: string) {
    const parsedMessage = parseXtMessage(message);
    if (parsedMessage.ok === false) {
      const reason = parsedMessage.reason;
      logverbose(getRedString(`malformed XT: ${reason}`));
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'error',
        source: 'xt-handler',
        direction: 'in',
        status: 'malformed-message',
        reason,
        messageLength: message.length
      });
      return;
    }

    const { name: wireAction, args } = parsedMessage.value;
    const action = canonicalizeXtAction(wireAction);
    const aliased = action !== wireAction;

    publishWaddleLiveTrace({
      category: 'XT',
      phase: 'request',
      source: 'xt-handler',
      action: wireAction,
      canonicalAction: aliased ? action : undefined,
      direction: 'in',
      argCount: args.length,
      messageLength: message.length
    });

    if ('penguin' in context) {
      logverbose(getBlueString(`incoming XT [${context.penguin.name}]: `), wireAction, args);
    }

    const callbacks = this._callbacks.get(action);

    if (callbacks !== undefined) {
      const callbackInfo = callbacks.find(([[contextTester, guard]]) => contextTester(context) ? guard(context) : false);
      if (callbackInfo === undefined) {
        logverbose(getRedString('unhandled XT for given context: ' + Object.keys(context).join(';')));
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'error',
          source: 'xt-handler',
          action: wireAction,
          canonicalAction: aliased ? action : undefined,
          direction: 'in',
          status: 'unhandled-context',
          argCount: args.length,
          contextKeys: Object.keys(context)
        });
        return;
      }

      const [_, signature, callback] = callbackInfo;

      // Airtower serializes an empty payload array as a final empty field.
      const emptyArrayFraming = Array.isArray(signature) && signature.length === 0 && args.length === 1 && args[0] === '';
      const argsForParsing = emptyArrayFraming ? [] : args;
      const parsedArgs = parseArgs(argsForParsing, signature);
      // Compatibility is evaluated against the canonical action. This lets the
      // native Halloween/MayParty cookie selector [0] reuse the verified late-AS3
      // rule without weakening signature checks for any unrelated namespace.
      const compatibility = parsedArgs === null ? getXtCompatibilityRule(action, args) : undefined;
      if (parsedArgs === null && compatibility === undefined) {
        logverbose(getRedString('incorrect type signature: ' + wireAction));
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'error',
          source: 'xt-handler',
          action: wireAction,
          canonicalAction: aliased ? action : undefined,
          direction: 'in',
          status: 'invalid-signature',
          argCount: args.length
        });
        return;
      }

      const dispatchArgs = parsedArgs ?? [];
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'handled',
        source: 'xt-handler',
        action: wireAction,
        canonicalAction: aliased ? action : undefined,
        direction: 'in',
        status: aliased
          ? 'compatibility-action-alias'
          : emptyArrayFraming
            ? 'empty-array-framing'
            : compatibility === undefined
              ? 'handler-dispatched'
              : 'compatibility-signature',
        argCount: dispatchArgs.length,
        receivedArgCount: args.length,
        compatibilityReason: aliased
          ? `native late-AS3 party namespace mapped to ${action}`
          : emptyArrayFraming
            ? 'Airtower encoded an empty argument array as a trailing empty XT payload field'
            : compatibility?.reason
      });

      try {
        const result = callback.call(client, context, wireAction, ...dispatchArgs);
        void Promise.resolve(result).then(() => {
          publishWaddleLiveTrace({
            category: 'XT',
            phase: 'handled',
            source: 'xt-handler',
            action: wireAction,
            canonicalAction: aliased ? action : undefined,
            direction: 'in',
            status: 'handler-complete',
            argCount: dispatchArgs.length,
            receivedArgCount: args.length,
            compatibility: aliased || compatibility !== undefined || emptyArrayFraming
          });
        }).catch(error => {
          publishWaddleLiveTrace({
            category: 'XT',
            phase: 'error',
            source: 'xt-handler',
            action: wireAction,
            canonicalAction: aliased ? action : undefined,
            direction: 'in',
            status: 'handler-threw',
            async: true,
            error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
          });
          throw error;
        });
      } catch (error) {
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'error',
          source: 'xt-handler',
          action: wireAction,
          canonicalAction: aliased ? action : undefined,
          direction: 'in',
          status: 'handler-threw',
          error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
        });
        throw error;
      }
    } else {
      if ('penguin' in context) {
        const fallback = getXtReadOnlyFallback(action);
        if (fallback !== undefined) {
          context.msg.send(context.penguin, fallback.responseAction, ...fallback.responseArgs);
          publishWaddleLiveTrace({
            category: 'XT',
            phase: 'handled',
            source: 'xt-handler',
            action: wireAction,
            canonicalAction: aliased ? action : undefined,
            direction: 'in',
            status: 'compatibility-response',
            argCount: args.length,
            responseAction: fallback.responseAction,
            compatibilityReason: fallback.reason
          });
          return;
        }
      }

      if (isNoResponseClientPacket(action)) {
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'handled',
          source: 'xt-handler',
          action: wireAction,
          canonicalAction: aliased ? action : undefined,
          direction: 'in',
          status: 'protocol-acknowledged',
          argCount: args.length
        });
      } else {
        logverbose(getRedString('unhandled XT: ' + wireAction));
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'error',
          source: 'xt-handler',
          action: wireAction,
          canonicalAction: aliased ? action : undefined,
          direction: 'in',
          status: 'unhandled-action',
          argCount: args.length
        });
      }
    }
  }

  public async disconnect(context: WorldContext) {
    await this._disconnect(context);
  }
}
