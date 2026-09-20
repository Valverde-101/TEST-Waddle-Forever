import zlib from 'zlib';

/**
 * The original 2015 Daily Spin AS2 SWFs require a clubpenguin.com URL.
 * On Waddle's loopback server their Security.checkDomain code calls
 * _root.loadMovie() with no URL, resulting in GET /undefined and a blank game.
 *
 * Adapt only the embedded, standalone comparison literal in the HTTP response
 * to the current five-digit loopback host. Source SWFs, SHA-256 manifests,
 * Halloween, mods and other minigames are never rewritten.
 */
const LEGACY_DOMAIN = 'clubpenguin.com';
const DOMAIN_BYTES = Array.from(LEGACY_DOMAIN + '\0', c => c.charCodeAt(0));
const LOCAL_HOST = /^(?:127\.0\.0\.1|localhost):[0-9]{5}$/;

/**
 * The TypeScript 7 toolchain and the installed Node typings disagree on
 * Buffer's ArrayBufferLike generic. An owned standard Uint8Array avoids that
 * incompatibility and ensures the zlib inputs have an ordinary ArrayBuffer.
 */
const ownedBytes = (source: ArrayLike<number>): Uint8Array<ArrayBuffer> => {
  const bytes = new Uint8Array(new ArrayBuffer(source.length));
  for (let index = 0; index < source.length; index++) bytes[index] = source[index];
  return bytes;
};

const isPartOfLongerDomain = (preceding: number): boolean =>
  /[a-zA-Z0-9.\/:*_-]/.test(String.fromCharCode(preceding));

export const patchFair2015GameSecurity = (original: Buffer, host: string): Buffer => {
  // Equal-length substitution preserves each AVM1 action and SWF tag length.
  if (!LOCAL_HOST.test(host) || host.length !== LEGACY_DOMAIN.length) {
    throw new Error('The Fair Daily Spin requires a five-digit local Waddle port');
  }

  const signature = original.toString('ascii', 0, 3);
  if (signature !== 'CWS' && signature !== 'FWS') {
    throw new Error('Unexpected Daily Spin SWF compression');
  }

  const sourceBody = original.subarray(8);
  const body = signature === 'CWS'
    ? ownedBytes(zlib.inflateSync(ownedBytes(sourceBody)))
    : ownedBytes(sourceBody);
  if (body.length + 8 !== original.readUInt32LE(4)) {
    throw new Error('Invalid decompressed Daily Spin SWF length');
  }

  // Search the literal only as a complete null-terminated AVM1 string.
  // In particular, never replace the substring in play.clubpenguin.com.
  const matches: number[] = [];
  for (let index = 0; index <= body.length - DOMAIN_BYTES.length; index++) {
    if (body[index] !== DOMAIN_BYTES[0]) continue;
    let same = true;
    for (let offset = 1; offset < DOMAIN_BYTES.length; offset++) {
      if (body[index + offset] !== DOMAIN_BYTES[offset]) {
        same = false;
        break;
      }
    }
    if (same && (index === 0 || !isPartOfLongerDomain(body[index - 1]))) {
      matches.push(index);
    }
  }

  // Assets without this guard need no transformation.
  if (matches.length === 0) return original;
  if (matches.length !== 1) {
    throw new Error('Ambiguous Daily Spin domain comparison: ' + matches.length);
  }

  const localHostBytes = Array.from(host, c => c.charCodeAt(0));
  body.set(localHostBytes, matches[0]);

  const payload = signature === 'CWS'
    ? ownedBytes(zlib.deflateSync(body))
    : body;
  const result = new Uint8Array(new ArrayBuffer(payload.length + 8));
  result.set(ownedBytes(original.subarray(0, 8)), 0);
  result.set(payload, 8);
  return Buffer.from(result.buffer);
};
