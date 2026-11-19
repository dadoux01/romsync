// Language of the site (docs/SPEC.md, "Langues"): the browser's by default,
// or the one chosen by the user, kept in this browser. Reading t() in a
// template makes it follow a change of language at once.

import { en } from './en';
import { fr, type Messages } from './fr';

export type Language = 'fr' | 'en';
export type LanguageChoice = Language | 'system';
export type Key = keyof Messages;

export const LANGUAGES: Record<Language, Messages> = { fr, en };
/** Name of each language, in that language. */
export const LANGUAGE_NAMES: Record<Language, string> = { fr: 'Français', en: 'English' };

const STORAGE_KEY = 'romsync-language';

/** The first supported language of the browser, English otherwise. */
export function browserLanguage(languages: readonly string[] = typeof navigator === 'undefined' ? [] : navigator.languages): Language {
  for (const l of languages) {
    const base = l.toLowerCase().split('-')[0];
    if (base in LANGUAGES) return base as Language;
  }
  return 'en';
}

function storedChoice(): LanguageChoice {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    if (v === 'fr' || v === 'en') return v;
  } catch {
    /* storage unavailable: follow the browser */
  }
  return 'system';
}

const state = $state<{ choice: LanguageChoice }>({ choice: storedChoice() });

export function languageChoice(): LanguageChoice {
  return state.choice;
}

export function language(): Language {
  return state.choice === 'system' ? browserLanguage() : state.choice;
}

/** BCP 47 tag for Intl formatting. */
export function locale(): string {
  return language() === 'fr' ? 'fr-FR' : 'en';
}

export function setLanguage(choice: LanguageChoice) {
  state.choice = choice;
  try {
    if (choice === 'system') localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, choice);
  } catch {
    /* not kept: only this page follows the choice */
  }
  syncDocumentLanguage();
}

/** Sets <html lang>, for screen readers and hyphenation. */
export function syncDocumentLanguage() {
  if (typeof document !== 'undefined') document.documentElement.lang = language();
}

/** Replaces each {name} of text with params[name]. */
export function format(text: string, params?: Record<string, string | number>): string {
  if (!params) return text;
  return text.replace(/\{(\w+)\}/g, (m, name: string) => (name in params ? String(params[name]) : m));
}

/** The text of key in the current language. */
export function t(key: Key, params?: Record<string, string | number>): string {
  return format(LANGUAGES[language()][key], params);
}

/** Whether key exists, for codes coming from the server (error codes, regions). */
export function hasKey(key: string): key is Key {
  return key in fr;
}
