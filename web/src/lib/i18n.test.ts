import { afterEach, describe, expect, it } from 'vitest';
import { LANGUAGES, browserLanguage, format, setLanguage, t } from './i18n/index.svelte';
import { fr } from './i18n/fr';
import { describePolicy, describeSizeEvent, formatSize } from './format';
import { regionName } from './saves';

const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

describe('translations', () => {
  afterEach(() => setLanguage('system'));

  it('have every key of French, with the same placeholders', () => {
    for (const [lang, messages] of Object.entries(LANGUAGES)) {
      expect(Object.keys(messages).sort(), lang).toEqual(Object.keys(fr).sort());
      for (const [key, text] of Object.entries(fr)) {
        expect(placeholders(messages[key as keyof typeof fr]), `${lang} ${key}`).toEqual(placeholders(text));
        expect(messages[key as keyof typeof fr].trim(), `${lang} ${key}`).not.toBe('');
      }
    }
  });

  it('follow the browser, English for other languages', () => {
    expect(browserLanguage(['fr-CA', 'en'])).toBe('fr');
    expect(browserLanguage(['de-DE', 'en-US'])).toBe('en');
    expect(browserLanguage(['de-DE'])).toBe('en');
    expect(browserLanguage([])).toBe('en');
  });

  it('fill placeholders and switch language at once', () => {
    expect(format('{a} et {b}, {c}', { a: 1, b: 'x' })).toBe('1 et x, {c}');
    setLanguage('fr');
    expect(t('policy.lastN', { n: 5 })).toBe('les 5 dernières versions');
    setLanguage('en');
    expect(t('policy.lastN', { n: 5 })).toBe('the last 5 versions');
    expect(describePolicy({ mode: 'days', n: 3 })).toBe('versions less than 3 days old');
  });

  it('format sizes in each language', () => {
    setLanguage('fr');
    expect(formatSize(1536)).toBe('1,5 Kio');
    expect(describeSizeEvent({ type: 'forced', from: 512 }, 8192)).toBe('Taille forcée depuis le site (avant : 512 o).');
    expect(regionName('D')).toBe('Allemagne');
    setLanguage('en');
    expect(formatSize(1536)).toBe('1.5 KiB');
    expect(formatSize(8 * 1024 * 1024)).toBe('8 MiB');
    expect(regionName('D')).toBe('Germany');
    expect(regionName('Z')).toBeNull();
    expect(regionName(null)).toBeNull();
  });
});
