import { describe, expect, it } from 'vitest';
import { sha256Pure } from './sha256';
import { isDeSmuME, parseRomHeader, isValidGameCode, rawSize } from './saves';
import { formatSize } from './format';
import { createHash } from 'node:crypto';

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
    expect(parseRomHeader(h)).toEqual({ title: 'POKEMON B', code: 'IRBF' });
    const homebrew = new Uint8Array(512);
    homebrew.set(enc.encode('####'), 0x0c);
    expect(parseRomHeader(homebrew)).toBeNull();
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
    expect(formatSize(512)).toBe('512 o');
    expect(formatSize(8192)).toBe('8 Kio');
    expect(formatSize(524288)).toBe('512 Kio');
    expect(formatSize(8 * 1024 * 1024)).toBe('8 Mio');
  });
});
