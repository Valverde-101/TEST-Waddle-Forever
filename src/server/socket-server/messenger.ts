import { getGreenString, getYellowString, logverbose } from "@server/logger";
import { ClientSocket } from "@server/socket-server/socket-server";
import { WorldPenguin } from "@server/socket-server/world/world-penguin";
import { publishWaddleLiveTrace } from "@common/live-trace";

const getXtMessageLastless = (handler: string, ...args: Array<number | string>): string => {
  return `%xt%${handler}%-1%` + args.join('%');
}

const getXtMessage = (handler: string, ...args: Array<number | string>): string => {
  return getXtMessageLastless(handler, ...args) + '%';
}

export class PenguinMessenger {
  private _clients = new Map<WorldPenguin, ClientSocket>();
  private _penguins = new Map<ClientSocket, WorldPenguin>();

  public getPenguin(client: ClientSocket) {
    return this._penguins.get(client);
  }

  public linkClient(client: ClientSocket, penguin: WorldPenguin) {
    this._clients.set(penguin, client);
    this._penguins.set(client, penguin);
  }

  public unlinkClient(penguin: WorldPenguin): void {
    const client = this._clients.get(penguin);
    if (client !== undefined) {
      this._penguins.delete(client);
    }
    this._clients.delete(penguin);
  }

  private async write(ps: WorldPenguin | ClientSocket | Array<ClientSocket | WorldPenguin>, message: string): Promise<void> {
    const recipients = Array.isArray(ps) ? ps : [ps];
    const clients = recipients.map(recipient => {
      if (!(recipient instanceof WorldPenguin)) {
        return recipient;
      }

      const client = this._clients.get(recipient);
      if (client === undefined) {
        // Optional chaining here used to turn a missing binding into `undefined`
        // inside Promise.all(), which resolves successfully. The caller would
        // then emit status=sent even though the packet was silently discarded.
        throw new Error('No client socket bound to penguin');
      }
      return client;
    });

    await Promise.all(clients.map(client => client.write(message)));
  }

  public async send(penguins: WorldPenguin | ClientSocket | Array<ClientSocket | WorldPenguin>, message: string, ...args: Array<string | number>): Promise<void> {
    logverbose(getGreenString('sending XT: '), message, args);
    const startedAt = Date.now();
    const recipientCount = Array.isArray(penguins) ? penguins.length : 1;
    try {
      await this.write(penguins, getXtMessage(message, ...args));
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'response',
        source: 'messenger',
        action: message,
        direction: 'out',
        status: 'sent',
        argCount: args.length,
        recipientCount,
        durationMs: Date.now() - startedAt
      });
    } catch (error) {
      publishWaddleLiveTrace({
        category: 'XT',
        phase: 'error',
        source: 'messenger',
        action: message,
        direction: 'out',
        status: 'send-failed',
        argCount: args.length,
        recipientCount,
        durationMs: Date.now() - startedAt,
        error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
      });
      throw error;
    }
  }

  public async sendXml(client: ClientSocket, action: string, body: string, room?: number) {
    const roomString = room === undefined ? '' : ` r="${room}"`;
    const xml = `<msg t="sys"><body action="${action}"${roomString}>${body}</body></msg>`;
    logverbose(getYellowString('Sending XML: '), xml);
    const startedAt = Date.now();
    try {
      await this.write(client, xml);
      publishWaddleLiveTrace({
        category: 'XML',
        phase: 'response',
        source: 'messenger',
        action,
        direction: 'out',
        status: 'sent',
        bodyLength: body.length,
        recipientCount: 1,
        durationMs: Date.now() - startedAt
      });
    } catch (error) {
      publishWaddleLiveTrace({
        category: 'XML',
        phase: 'error',
        source: 'messenger',
        action,
        direction: 'out',
        status: 'send-failed',
        bodyLength: body.length,
        recipientCount: 1,
        durationMs: Date.now() - startedAt,
        error: error instanceof Error ? `${error.name}: ${error.message}` : String(error)
      });
      throw error;
    }
  }

  public close() {
    for (const client of this._clients.values()) {
      client.end();
    }
  }

  public getClients(): ClientSocket[] {
    return [...this._clients.values()];
  }

  public getClient(p: WorldPenguin): ClientSocket {
    const cs = this._clients.get(p);
    if (cs === undefined) {
      throw new Error('No client socket bound to penguin');
    }
    return cs;
  }
}