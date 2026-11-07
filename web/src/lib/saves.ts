// Detection of save formats and NDS ROM headers, done locally in the browser.

const DESMUME_COOKIE = '|-DESMUME SAVE-|';
const DESMUME_FOOTER_LENGTH = 122;

/** True when the file ends with a DeSmuME footer (.dsv). */
export function isDeSmuME(data: Uint8Array): boolean {
  if (data.length < DESMUME_FOOTER_LENGTH) return false;
  const tail = data.subarray(data.length - DESMUME_COOKIE.length);
  for (let i = 0; i < DESMUME_COOKIE.length; i++) {
    if (tail[i] !== DESMUME_COOKIE.charCodeAt(i)) return false;
  }
  return true;
}

/** Size of the raw save contained in a file of the given profile. */
export function rawSize(data: Uint8Array, profile: string): number {
  return profile === 'desmume' ? data.length - DESMUME_FOOTER_LENGTH : data.length;
}

export interface RomHeader {
  title: string;
  code: string;
}

const CODE_RE = /^[A-Z0-9]{4}$/;

/**
 * Reads the title and game code from the first bytes of a .nds ROM
 * (title at 0x000, 12 bytes; game code at 0x00C, 4 bytes). Returns null when
 * the header has no valid code (homebrew), in which case the user must type
 * an identifier.
 */
export function parseRomHeader(header: Uint8Array): RomHeader | null {
  if (header.length < 0x10) return null;
  const ascii = (from: number, to: number) =>
    String.fromCharCode(...header.subarray(from, to)).replace(/\0+$/, '').trim();
  const code = ascii(0x0c, 0x10);
  if (!CODE_RE.test(code) || code === '####') return null;
  return { title: ascii(0x00, 0x0c), code };
}

const GAME_CODE_RE = /^([A-Z0-9]{4}|h:[0-9a-f]{40}|x:[a-z0-9-]{1,32})$/;

export function isValidGameCode(code: string): boolean {
  return GAME_CODE_RE.test(code);
}

/** Region names for the fourth character of a cartridge code. */
export const REGIONS: Record<string, string> = {
  E: 'USA',
  P: 'Europe',
  F: 'France',
  D: 'Allemagne',
  S: 'Espagne',
  I: 'Italie',
  J: 'Japon',
  K: 'Corée',
  U: 'Australie',
  O: 'International',
};
