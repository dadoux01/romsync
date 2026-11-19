import { describe, expect, it } from 'vitest';
import { sha256Pure } from './sha256';
import { hasMgbaClock, isDeSmuME, parseRomHeader, isValidGameCode, profileFor, rawSize, systemOf, withSystem } from './saves';
import { formatSize } from './format';
import { setLanguage } from './i18n/index.svelte';
import { createHash } from 'node:crypto';
import { sha1Pure } from './sha1';

const enc = new TextEncoder();

describe('sha256Pure', () => {
  it('matches known vectors', () => {
    expect(sha256Pure(new Uint8Array())).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(sha256Pure(enc.encode('abc'))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
  it('matches node crypto on save-sized inputs', () => {
    for (const n of [55, 56, 63, 64, 65, 512, 8192, 524288]) {
      const data = new Uint8Array(n).map((_, i) => (i * 31) & 0xff);
      expect(sha256Pure(data)).toBe(createHash('sha256').update(data).digest('hex'));
    }
  });
});

describe('save detection', () => {
  const footer = enc.encode(
    '|<--Snip above here to create a raw sav by excluding this DeSmuME savedata footer:' +
      '\0'.repeat(24) +
      '|-DESMUME SAVE-|',
  );
  it('recognises DeSmuME files', () => {
    const dsv = new Uint8Array(512 + footer.length);
    dsv.set(footer, 512);
    expect(footer.length).toBe(122);
    expect(isDeSmuME(dsv)).toBe(true);
    expect(rawSize(dsv, 'desmume')).toBe(512);
    expect(isDeSmuME(new Uint8Array(512))).toBe(false);
  });
  it('reads NDS headers', () => {
    const h = new Uint8Array(512);
    h.set(enc.encode('POKEMON B'), 0);
    h.set(enc.encode('IRBF'), 0x0c);
    expect(parseRomHeader(h)).toEqual({ title: 'POKEMON B', code: 'IRBF', system: 'nds' });
    const homebrew = new Uint8Array(512);
    homebrew.set(enc.encode('####'), 0x0c);
    expect(parseRomHeader(homebrew)).toBeNull();
  });
  it('reads GBA headers', () => {
    const h = new Uint8Array(512);
    h.set(enc.encode('POKEMON EMER'), 0xa0);
    h.set(enc.encode('BPEF'), 0xac);
    h[0xb2] = 0x96;
    expect(parseRomHeader(h)).toEqual({ title: 'POKEMON EMER', code: 'BPEF', system: 'gba' });
    // The file name is enough, even without the fixed byte.
    h[0xb2] = 0;
    expect(parseRomHeader(h, 'Emeraude.GBA')?.system).toBe('gba');
  });
  it('prefixes the identifiers of other consoles than the DS', () => {
    expect(withSystem('nds', 'IRBF')).toBe('IRBF');
    expect(withSystem('gba', 'BPEF')).toBe('gba:BPEF');
    expect(systemOf('gba:x:hack')).toBe('gba');
    expect(systemOf('x:hack')).toBe('nds');
    expect(isValidGameCode('gba:BPEF')).toBe(true);
    expect(isValidGameCode('gba:bpef')).toBe(false);
  });
  it("recognises mGBA's cartridge clock", () => {
    const withClock = new Uint8Array(32768 + 16);
    expect(hasMgbaClock(withClock)).toBe(true);
    expect(hasMgbaClock(new Uint8Array(32768))).toBe(false);
    expect(profileFor('gba', withClock)).toBe('mgba');
    expect(rawSize(withClock, 'mgba')).toBe(32768);
    expect(profileFor('nds', new Uint8Array(512))).toBe('raw');
  });
  it('validates game codes like the server', () => {
    expect(isValidGameCode('IRBF')).toBe(true);
    expect(isValidGameCode('h:' + 'a'.repeat(40))).toBe(true);
    expect(isValidGameCode('x:my-hack')).toBe(true);
    expect(isValidGameCode('irbf')).toBe(false);
    expect(isValidGameCode('x:My_Hack')).toBe(false);
  });
});

describe('formatSize', () => {
  it('uses binary units', () => {
    setLanguage('fr');
    expect(formatSize(512)).toBe('512 o');
    expect(formatSize(8192)).toBe('8 Kio');
    expect(formatSize(524288)).toBe('512 Kio');
    expect(formatSize(8 * 1024 * 1024)).toBe('8 Mio');
  });
});

describe('versions', () => {
  it('orders releases and pre-releases', async () => {
    const { isNewer, parseVersion } = await import('./version');
    expect(isNewer('0.5.0', '0.4.0')).toBe(true);
    expect(isNewer('0.5.0', '0.5.0-rc1')).toBe(true);
    expect(isNewer('0.5.0-rc2', '0.5.0-rc1')).toBe(true);
    expect(isNewer('0.10.0', '0.9.9')).toBe(true);
    expect(isNewer('0.4.0', '0.5.0')).toBe(false);
    expect(isNewer('0.5.0', '0.5.0')).toBe(false);
    expect(isNewer('0.5.0', 'dev')).toBe(false);
    expect(parseVersion('1.02.0')).toBeNull();
  });
});

describe('Game Boy', () => {
  it('computes SHA-1 like node', () => {
    for (const n of [0, 55, 56, 64, 1000, 32768]) {
      const data = new Uint8Array(n).map((_, i) => (i * 13) & 0xff);
      expect(sha1Pure(data)).toBe(createHash('sha1').update(data).digest('hex'));
    }
  });
  it('has no cartridge code', async () => {
    const { isValidGameCode, systemOf, systemOfRomName, profileFor, rawSize, parseRomHeader } = await import('./saves');
    expect(isValidGameCode('gb:x:red')).toBe(true);
    expect(isValidGameCode('gb:APSE')).toBe(false);
    expect(systemOf('gb:h:' + 'a'.repeat(40))).toBe('gb');
    expect(systemOfRomName('Cristal.gbc')).toBe('gb');
    expect(parseRomHeader(new Uint8Array(512), 'Rouge.gb')).toBeNull();
    const withClock = new Uint8Array(8192 + 48);
    expect(profileFor('gb', withClock)).toBe('mgba-gb');
    expect(rawSize(withClock, 'mgba-gb')).toBe(8192);
  });
});

describe('3DS', () => {
  it('identifies games by their title ID and exchanges a .tar', async () => {
    const { isValidGameCode, systemOf, isTreeSystem, profileFor } = await import('./saves');
    expect(isValidGameCode('3ds:0004000000055D00')).toBe(true);
    expect(isValidGameCode('3ds:0004000000055d00')).toBe(false);
    expect(isValidGameCode('3ds:h:' + 'a'.repeat(40))).toBe(false);
    expect(systemOf('3ds:x:y')).toBe('3ds');
    expect(isTreeSystem('3ds')).toBe(true);
    expect(profileFor('3ds', new Uint8Array(1024))).toBe('raw');
  });
});
