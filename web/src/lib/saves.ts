import { hasKey, t } from './i18n/index.svelte';

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

/** Consoles of RomSync (docs/SPEC.md, "Multi-consoles"). */
export type GameSystem = 'nds' | 'gba' | 'gb';
export const SYSTEMS: GameSystem[] = ['nds', 'gba', 'gb'];

/** Console of a game identifier: its prefix, none for the DS. */
export function systemOf(code: string): GameSystem {
  if (code.startsWith('gba:')) return 'gba';
  if (code.startsWith('gb:')) return 'gb';
  return 'nds';
}

/** Consoles whose ROM header has no game code: identified by the SHA-1 of the ROM. */
export function hasCartridgeCode(system: GameSystem): boolean {
  return system !== 'gb';
}

/** Console of a ROM file name, or null. */
export function systemOfRomName(name: string): GameSystem | null {
  const n = name.toLowerCase();
  if (n.endsWith('.gba')) return 'gba';
  if (n.endsWith('.gb') || n.endsWith('.gbc') || n.endsWith('.sgb')) return 'gb';
  if (n.endsWith('.nds') || n.endsWith('.dsi') || n.endsWith('.srl')) return 'nds';
  return null;
}

/** Game identifier of a console from its identifier without prefix. */
export function withSystem(system: GameSystem, local: string): string {
  return system === 'nds' ? local : `${system}:${local}`;
}

/** mGBA's cartridge clock, after the save: 16 bytes on the GBA, 48 on the Game Boy. */
const MGBA_CLOCK_LENGTH: Record<string, number> = { mgba: 16, 'mgba-gb': 48 };

/** Whether a file of the mgba or mgba-gb profile ends with the cartridge clock (size modulo 256). */
export function hasMgbaClock(data: Uint8Array, profile = 'mgba'): boolean {
  const n = MGBA_CLOCK_LENGTH[profile] ?? 0;
  return n > 0 && data.length > n && data.length % 256 === n;
}

/** Upload profile of a save file for a console: the server removes the DeSmuME footer or mGBA's clock. */
export function profileFor(system: GameSystem, data: Uint8Array): 'raw' | 'desmume' | 'mgba' | 'mgba-gb' {
  if (system === 'gba') return 'mgba';
  if (system === 'gb') return 'mgba-gb';
  return isDeSmuME(data) ? 'desmume' : 'raw';
}

/** Size of the raw save contained in a file of the given profile. */
export function rawSize(data: Uint8Array, profile: string): number {
  if (profile === 'desmume') return data.length - DESMUME_FOOTER_LENGTH;
  if (hasMgbaClock(data, profile)) return data.length - MGBA_CLOCK_LENGTH[profile];
  return data.length;
}

export interface RomHeader {
  title: string;
  /** Cartridge code, without the console prefix. */
  code: string;
  system: GameSystem;
}

const CODE_RE = /^[A-Z0-9]{4}$/;

/**
 * Reads the title and game code from the first bytes of a ROM: a .gba
 * (title at 0x0A0, 12 bytes; code at 0x0AC; fixed byte 0x96 at 0x0B2) or a
 * .nds (title at 0x000, 12 bytes; code at 0x00C). Returns null when the
 * header has no valid code (homebrew), in which case the user must type an
 * identifier.
 */
/** Title of a Game Boy ROM header (0x134, up to 16 bytes). */
export function romTitleGb(header: Uint8Array): string {
  return String.fromCharCode(...header.subarray(0x134, 0x144).map((c) => (c >= 0x20 && c < 0x7f ? c : 0)))
    .replace(/\0/g, '')
    .trim();
}

export function parseRomHeader(header: Uint8Array, fileName = ''): RomHeader | null {
  // The Game Boy has no game code: its identifier is the SHA-1 of the ROM.
  if (systemOfRomName(fileName) === 'gb') return null;
  const ascii = (from: number, to: number) =>
    String.fromCharCode(...header.subarray(from, to)).replace(/\0+$/, '').trim();
  const gba = fileName.toLowerCase().endsWith('.gba') || (header.length > 0xb2 && header[0xb2] === 0x96);
  const [title, code] = gba ? [ascii(0xa0, 0xac), ascii(0xac, 0xb0)] : [ascii(0x00, 0x0c), ascii(0x0c, 0x10)];
  if (header.length < (gba ? 0xb0 : 0x10) || !CODE_RE.test(code) || code === '####') return null;
  return { title, code, system: gba ? 'gba' : 'nds' };
}

const GAME_CODE_RE = /^((gba:)?[A-Z0-9]{4}|((gba|gb):)?(h:[0-9a-f]{40}|x:[a-z0-9-]{1,32}))$/;

export function isValidGameCode(code: string): boolean {
  return GAME_CODE_RE.test(code);
}

/** Region name for the fourth character of a cartridge code, or null. */
export function regionName(region: string | null | undefined): string | null {
  const key = `region.${region}`;
  return region && hasKey(key) ? t(key) : null;
}
