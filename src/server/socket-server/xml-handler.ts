import { PenguinMessenger } from "@server/socket-server/messenger"
import { World } from "./world/world"
import { GameData } from "@server/timelines/game-data"
import { SettingsManager } from "@server/settings"
import { PenguinRepository } from "@server/database/database"
import { ClientSocket } from "./socket-server"
import { getYellowString, logverbose } from "@server/logger"
import { OfflineWorld } from "./offline-world"
import { publishWaddleLiveTrace } from "@common/live-trace"

export type LoginContext = {
  msg: PenguinMessenger,
  data: GameData,
  settings: SettingsManager,
  db: PenguinRepository,
  client: ClientSocket,
} & ({} | { world: World; off: OfflineWorld; });

const parseXmlMessage = (message: string): [string, string] => {
  if (message === '<policy-file-request/>') {
    return ['policy', message];
  } else {
    const actionMatch = message.match(/action='(\w+)'/);
    const action = actionMatch === null ? '' : actionMatch[1];
    return [action, message];
  }
}

export class XmlHandler {
  constructor(private _callbacks: Map<string, (ctx: LoginContext, data: string) => void | Promise<void>>) {}

  public handle(context: LoginContext, message: string) {
    logverbose(getYellowString('Incoming XML data: '), message);
    const [action, data] = parseXmlMessage(message);
    publishWaddleLiveTrace({
      category: 'XML',
      phase: 'request',
      source: 'xml-handler',
      action: action || '(unknown)',
      direction: 'in',
      messageLength: message.length
    });

    const callback = this._callbacks.get(action);
    if (callback !== undefined) {
      publishWaddleLiveTrace({
        category: 'XML',
        phase: 'handled',
        source: 'xml-handler',
        action: action || '(unknown)',
        direction: 'in',
        status: 'handler-dispatched',
        messageLength: message.length
      });
      try {
        callback(context, data);
      } catch (error) {
        publishWaddleLiveTrace({
          category: 'XML',
          phase: 'error',
          source: 'xml-handler',
          action: action || '(unknown)',
          direction: 'in',
          status: 'handler-threw',
          error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
        });
        throw error;
      }
    } else {
      publishWaddleLiveTrace({
        category: 'XML',
        phase: 'error',
        source: 'xml-handler',
        action: action || '(unknown)',
        direction: 'in',
        status: 'unhandled-action',
        messageLength: message.length
      });
    }
  }
}