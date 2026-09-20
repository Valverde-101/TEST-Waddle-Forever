import zlib from 'zlib';

/**
 * Archived 2015 AS2 minigames include Security.checkDomain(), which only
 * recognizes clubpenguin.com in the original Flash URL. Waddle serves games
 * from its loopback HTTP server instead. On a non-approved origin the original
 * AVM1 code calls _root.loadMovie() with no URL (GET /undefined), destroying
 * the minigame before its actual assets are requested.
 *
 * Do not mutate the archived SWFs on disk or disable Flash/browser security.
 * Adapt only their self-contained, exact domain-comparison literal, in memory,
 * when served from Waddle's loopback endpoint. The original comparison and
 * parent validation remain in force. This is applied ONLY to Fair minigames.
 */
const LEGACY_DOMAIN = 'clubpenguin.com';
const DOMAIN_BYTES = Buffer.from(LEGACY_DOMAIN + '\0', 'ascii');
const LOCAL_HOST = /^(?:127\.0\.0\.1|localhost):[0-9]{5}$/;
const isPartOfLongerDomain = (preceding: number): boolean =>
  /[a-zA-Z0-9.\/:*_-]/.test(String.fromCharCode(preceding));

export const patchFair2015GameSecurity = (original: Buffer, host: string): Buffer => {
  // The original string and loopback host must have the same byte length.
  // Equal-length substitution keeps all AVM1 action and SWF tag offsets intact.
  if (!LOCAL_HOST.test(host) || Buffer.byteLength(host, 'ascii') !== LEGACY_DOMAIN.length) {
    throw new Error('The Fair minigame requires a five-digit local Waddle port');
  }

  const signature = original.toString('ascii', 0, 3);
  if (signature !== 'CWS' && signature !== 'FWS') {
    throw new Error('Unexpected SWF compression in The Fair minigame');
  }

  const body = signature === 'CWS'
    ? zlib.inflateSync(original.subarray(8))
    : Buffer.from(original.subarray(8));
  if (body.length + 8 !== original.readUInt32LE(4)) {
    throw new Error('Invalid decompressed Fair minigame SWF length');
  }

  // Do not alter occurrences inside play.clubpenguin.com, domain wildcards,
  // CDN links, etc. Only the standalone Security.checkDomain comparison.
  let replacements = 0;
  let start = 0;
  while (true) {
    const index = body.indexOf(DOMAIN_BYTES, start);
    if (index < 0) break;
    if (index === 0 || !isPartOfLongerDomain(body[index - 1])) {
      body.write(host, index, LEGACY_DOMAIN.length, 'ascii');
      replacements++;
    }
    start = index + DOMAIN_BYTES.length;
  }

  if (replacements === 0) {
    // Asset without an embedded Security.checkDomain: preserve it verbatim.
    return original;
  }
  if (replacements !== 1) {
    throw new Error('Ambiguous security domain literal in The Fair minigame: ' + replacements);
  }

  if (signature === 'FWS') {
    return Buffer.concat([original.subarray(0, 8), body]);
  }
  return Buffer.concat([original.subarray(0, 8), zlib.deflateSync(body)]);
};
