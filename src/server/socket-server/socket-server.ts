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
const httpHeaderTerminator = Buffer.from('\r\n\r\n', 'ascii');

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
        });
      });

      ws.on('error', console.error);
    });
  
    net.createServer((socket) => {
      socket.once('data', (buffer) => {
        const looksLikeHttp = buffer.length >= 3 && buffer.subarray(0, 3).toString('ascii') === 'GET';

        if (looksLikeHttp) {
          // Keep the post-header WebSocket "head" as the exact original bytes.
          // Converting the entire TCP packet to UTF-8 and reconstructing it with
          // a single-byte encoding corrupts binary frame bytes when an eager
          // client sends its first WebSocket frame in the same packet as the
          // HTTP upgrade request.
          const headerEnd = buffer.indexOf(httpHeaderTerminator);
          if (headerEnd === -1) {
            socket.destroy();
            return;
          }

          const bodyOffset = headerEnd + httpHeaderTerminator.length;
          const requestText = buffer.subarray(0, bodyOffset).toString('utf8');
          const head = buffer.subarray(bodyOffset);
          const headers = parseHeaders(requestText);

          wsServer.handleUpgrade({
            headers,
            method: 'GET',
            socket,
            url: '/',
          }, socket, head, (ws) => {
            wsServer.emit('connection', ws, { headers, method: 'GET' });
          });
        } else {
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
            });
          });

          // Re-emit the data so the TCP handler gets the first packet too.
          socket.emit('data', buffer);

          socket.on('error', console.error);
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