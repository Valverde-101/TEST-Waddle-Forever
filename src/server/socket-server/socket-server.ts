import net from 'net';
import { WebSocketServer } from 'ws'

import { EffectService } from '@common/utils';

export interface MessageHandler {
  handle: (client: ClientSocket, message: string) => void;
  disconnect: (client: ClientSocket) => Promise<void>;
}

export interface ClientSocket {
  write: (data: string) => Promise<void>;
  end: (data?: string) => void;
  buffer: string;
}

const maxBufferedPacketChars = 4 * 1024 * 1024;
const maxHttpUpgradeHeaderBytes = 64 * 1024;
const httpUpgradeTimeoutMs = 10_000;
const httpHeaderTerminator = '\r\n\r\n';

const parseHeaders = (data: string): Record<string, string> => {
  const lines = data.split('\r\n');
  const entries: Array<[string, string]> = [];

  for (const line of lines.slice(1)) {
    const separator = line.indexOf(':');
    if (separator <= 0) continue;
    const key = line.slice(0, separator).trim().toLowerCase();
    const value = line.slice(separator + 1).trim();
    if (key && value) entries.push([key, value]);
  }
  
  return Object.fromEntries(entries);
}

export const setupSocketServer = async (name: string, port: number, handler: MessageHandler): Promise<EffectService<void>> => {
  await new Promise<void>((resolve, reject) => {
    const wsServer = new WebSocketServer({ noServer: true });
    
    wsServer.on('connection', (ws, req) => {
      console.log(`A client has connected to ${name} (WebSocket)`);

      const cs: ClientSocket = {
        write: async (message: string) => {
          return new Promise<void>((resolve, reject) => {
            ws.send(Buffer.from(message + '\0', 'utf8'), { binary: true }, (err) => {
              if (err) {
                reject(err);
                return;
              }
              resolve();
            });
          })
        },

        end: (d) => ws.close(undefined, d),
        buffer: ''
      }

      ws.on('message', (data) => {
        const str = data.toString();
        if (!str.startsWith('GET')) {
          handler.handle(cs, str);
        }
      });

      ws.on('close', () => {
        void handler.disconnect(cs).then(() => {
          console.log('A client has disconnected (WebSocket)');
        }).catch(error => {
          console.error('WebSocket disconnect handler failed', error);
          // Preserve the previous fail-fast contract. Runtime diagnostics will
          // classify the resulting unhandled rejection with the exact stack.
          throw error;
        });
      });

      ws.on('error', console.error);
    });
  
    net.createServer((socket) => {
      const startRawClient = (firstBuffer: Buffer) => {
        socket.setEncoding('utf8')
        console.log(`A client has connected to ${name}`);

        const cs: ClientSocket = {
          write: async (message: string) => {
            return new Promise<void>((resolve, reject) => {
              socket.write(message + '\0', (err) => {
                if (err) {
                  reject(err);
                  return;
                }
                resolve();
              });
            })
          },
          end: (d) => {
            if (d === undefined) {
              socket.end();
            } else {
              socket.end(d);
            }
          },
          buffer: ''
        }

        socket.on('data', (data: string | Buffer) => {
          const packets = (cs.buffer + data.toString()).split('\0');
          cs.buffer = packets.pop() ?? '';

          if (cs.buffer.length > maxBufferedPacketChars) {
            console.error(`${name} client exceeded pending packet buffer limit`);
            socket.destroy(new Error('Socket packet buffer limit exceeded'));
            return;
          }

          for (const packet of packets) {
            if (packet.length > 0) {
              handler.handle(cs, packet);
            }
          }
        });

        socket.on('close', () => {
          void handler.disconnect(cs).then(() => {
            console.log('A client has disconnected');
          }).catch(error => {
            console.error('TCP disconnect handler failed', error);
            throw error;
          });
        });

        socket.on('error', console.error);

        // The first chunk was consumed by protocol detection before the raw TCP
        // data listener existed. Re-emit it exactly once into the normal parser.
        socket.emit('data', firstBuffer);
      };

      const startWebSocketUpgrade = (firstBuffer: Buffer) => {
        // Normalize through number[] instead of Buffer<ArrayBufferLike> overloads.
        // The project intentionally combines TypeScript 7 with Node 18 typings;
        // direct Buffer-to-Buffer overloads can otherwise become incompatible
        // when one side is inferred with SharedArrayBuffer-capable generics.
        let pending = Buffer.from(Array.from(firstBuffer));
        let settled = false;
        const timeout = setTimeout(() => {
          if (settled) return;
          settled = true;
          socket.destroy(new Error('WebSocket upgrade header timeout'));
        }, httpUpgradeTimeoutMs);
        timeout.unref();

        const finish = () => {
          if (settled) return true;
          const headerEnd = pending.indexOf(httpHeaderTerminator, 0, 'ascii');
          if (headerEnd === -1) {
            if (pending.length > maxHttpUpgradeHeaderBytes) {
              settled = true;
              clearTimeout(timeout);
              socket.destroy(new Error('WebSocket upgrade headers too large'));
              return true;
            }
            return false;
          }

          settled = true;
          clearTimeout(timeout);
          const bodyOffset = headerEnd + Buffer.byteLength(httpHeaderTerminator, 'ascii');
          const requestText = pending.subarray(0, bodyOffset).toString('utf8');
          const head = pending.subarray(bodyOffset);
          const headers = parseHeaders(requestText);

          // Keep the post-header WebSocket "head" as the exact original bytes.
          // Converting the entire TCP packet to UTF-8 and reconstructing it with
          // a single-byte encoding corrupts binary frame bytes when an eager
          // client sends its first frame together with the upgrade request.
          wsServer.handleUpgrade({
            headers,
            method: 'GET',
            socket,
            url: '/',
          }, socket, head, (ws) => {
            wsServer.emit('connection', ws, { headers, method: 'GET' });
          });
          return true;
        };

        const readMore = () => {
          if (finish()) return;
          socket.once('data', (chunk: Buffer) => {
            pending = Buffer.from([...pending, ...chunk]);
            readMore();
          });
        };

        readMore();
      };

      socket.once('data', (buffer: Buffer) => {
        const looksLikeHttp = buffer.length >= 3 && buffer.subarray(0, 3).toString('ascii') === 'GET';
        if (looksLikeHttp) {
          // A TCP read is not an HTTP-message boundary. Accumulate fragmented
          // upgrade headers until CRLFCRLF rather than disconnecting clients
          // whose GET request happens to arrive in more than one network chunk.
          startWebSocketUpgrade(buffer);
        } else {
          startRawClient(buffer);
        }
      });
    }).listen(port, () => {
      console.log(`${name} server listening on port ${port}`);
      resolve();
    }).on('error', (err) => {
      reject(err)
    });
  })
}