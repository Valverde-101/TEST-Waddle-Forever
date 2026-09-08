import { ArgumentsIndicator, parseArgs } from "@server/socket-server/arg-parser";
import { ClientSocket } from "./socket-server";
import { WorldContext } from "@server/socket-server/handlers/handlers";
import { getBlueString, getRedString, logverbose } from "@server/logger";
import { publishWaddleLiveTrace } from "@common/live-trace";
import { getXtCompatibilityRule, isNoResponseClientPacket } from "./handlers/protocol";

const parseXtMessage = (message: string): [string, string[]] => {
  const values = message.split('%');
  if (values[1] !== 'xt') {
    throw new Error(`Invalid XT message: ${message}`);
  }

  const name = values.slice(2, 4).join('%');
  const args = values.slice(5, values.length - 1); // last is empty

  return [name, args];
}

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
  /**
   * In miliseconds, how much to wait before accepting the next packet
   * from the same client
   */
  cooldown?: number
}

class CallbackManager<Ctx extends WorldContext> {
  private _cooldown: number | null = null;
  private _once: boolean = false;
  private _handled = new Map<ClientSocket, boolean>();
  private _timestamps = new Map<ClientSocket, number>();

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
        console.log('Rate limited');
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

    if (this._once) {
      if (this._handled.get(client)) {
        console.log('Already handled');
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
    }

    // Commit acceptance state before entering game logic. The old implementation
    // checked these maps but never wrote to them, so `once` and `cooldown` were
    // effectively no-ops and repeated packets could execute the same handler
    // indefinitely. Marking before dispatch also closes the re-entrancy window
    // for back-to-back packets while an async handler is still running.
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
    const [name, args] = parseXtMessage(message);

    publishWaddleLiveTrace({
      category: 'XT',
      phase: 'request',
      source: 'xt-handler',
      action: name,
      direction: 'in',
      argCount: args.length,
      messageLength: message.length
    });
    
    if ('penguin' in context) {
      logverbose(getBlueString(`incoming XT [${context.penguin.name}]: `), name, args);
    }

    const callbacks = this._callbacks.get(name);

    if (callbacks !== undefined) {
      const callbackInfo = callbacks.find(([[contextTester, guard]]) => contextTester(context) ? guard(context) : false);
      if (callbackInfo === undefined) {
        logverbose(getRedString('unhandled XT for given context: ' + Object.keys(context).join(';')));
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'error',
          source: 'xt-handler',
          action: name,
          direction: 'in',
          status: 'unhandled-context',
          argCount: args.length,
          contextKeys: Object.keys(context)
        });
        return;
      }

      const [_, signature, callback] = callbackInfo;
      const parsedArgs = parseArgs(args, signature);
      const compatibility = parsedArgs === null ? getXtCompatibilityRule(name, args.length) : undefined;
      if (parsedArgs === null && compatibility === undefined) {
        logverbose(getRedString('incorrect type signature: ' + name));
        publishWaddleLiveTrace({
          category: 'XT',
          phase: 'error',
          source: 'xt-handler',
          action: name,
          direction: 'in',
          status: 'invalid-signature',
          argCount: args.length
        });
        return;
      }

      // Compatibility rules are explicit and read-only. Their extra arguments
      // are version metadata/pagination fields that the legacy Waddle callback
      // does not consume, so dispatch with the canonical parsed argument list.
      // For normal signatures parsedArgs remains authoritative.
      const dispatchArgs = parsedArgs ?? [];
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'handled',
        source: 'xt-handler',
        action: name,
        direction: 'in',
        status: compatibility === undefined ? 'handler-dispatched' : 'compatibility-signature',
        argCount: dispatchArgs.length,
        receivedArgCount: args.length,
        compatibilityReason: compatibility?.reason
      });
      try {
        const result = callback.call(client, context, name, ...dispatchArgs);
        void Promise.resolve(result).then(() => {
          publishWaddleLiveTrace({
            category: 'XT',
            phase: 'handled',
            source: 'xt-handler',
            action: name,
            direction: 'in',
            status: 'handler-complete',
            argCount: dispatchArgs.length,
            receivedArgCount: args.length,
            compatibility: compatibility !== undefined
          });
        }).catch(error => {
          publishWaddleLiveTrace({
            category: 'XT',
            phase: 'error',
            source: 'xt-handler',
            action: name,
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
          action: name,
          direction: 'in',
          status: 'handler-threw',
          error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
        });
        throw error;
      }
    } else if (isNoResponseClientPacket(name)) {
      // These packets are protocol acknowledgements/lifecycle notifications, not
      // missing gameplay handlers. Accepting them explicitly removes false
      // "unhandled-action" noise while preserving strict errors for everything
      // that really is unsupported.
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'handled',
        source: 'xt-handler',
        action: name,
        direction: 'in',
        status: 'protocol-acknowledged',
        argCount: args.length
      });
    } else {
      logverbose(getRedString('unhandled XT: ' + name));
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'error',
        source: 'xt-handler',
        action: name,
        direction: 'in',
        status: 'unhandled-action',
        argCount: args.length
      });
    }
  }

  public async disconnect(context: WorldContext) {
    await this._disconnect(context);
  }
}