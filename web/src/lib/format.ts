import { locale, t } from './i18n/index.svelte';

// Formatters per locale, built once each.
const cache = new Map<string, Intl.DateTimeFormat | Intl.RelativeTimeFormat | Intl.NumberFormat>();
function cached<T extends Intl.DateTimeFormat | Intl.RelativeTimeFormat | Intl.NumberFormat>(key: string, make: () => T): T {
  let f = cache.get(key);
  if (!f) cache.set(key, (f = make()));
  return f as T;
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const l = locale();
  return cached(`date:${l}`, () => new Intl.DateTimeFormat(l, { dateStyle: 'medium', timeStyle: 'short' })).format(new Date(iso));
}

export function relativeDate(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return t('common.never');
  const l = locale();
  const rtf = cached(`rel:${l}`, () => new Intl.RelativeTimeFormat(l, { numeric: 'auto' }));
  const diff = (new Date(iso).getTime() - now) / 1000;
  const abs = Math.abs(diff);
  if (abs < 60) return rtf.format(Math.round(diff), 'second');
  if (abs < 3600) return rtf.format(Math.round(diff / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(diff / 3600), 'hour');
  if (abs < 86400 * 30) return rtf.format(Math.round(diff / 86400), 'day');
  return formatDate(iso);
}

/** Binary units, with the decimal separator of the language ("1,5 Kio", "1.5 KiB"). */
export function formatSize(bytes: number | null | undefined): string {
  if (bytes == null) return '—';
  const l = locale();
  const num = cached(`num:${l}`, () => new Intl.NumberFormat(l, { maximumFractionDigits: 1 }));
  if (bytes < 1024) return t('size.bytes', { n: num.format(bytes) });
  if (bytes < 1024 * 1024) return t('size.kib', { n: num.format(bytes / 1024) });
  return t('size.mib', { n: num.format(bytes / 1024 / 1024) });
}

/** Describes the size event of a version, for the history. */
export function describeSizeEvent(e: { type: string; from: number }, size: number): string {
  const params = { from: formatSize(e.from), size: formatSize(size) };
  switch (e.type) {
    case 'trimmed':
      return t('sizeEvent.trimmed', params);
    case 'shrunk':
      return t('sizeEvent.shrunk', params);
    case 'forced':
      return t('sizeEvent.forced', params);
    default:
      return '';
  }
}

export function shortHash(hash: string): string {
  return hash.slice(0, 10);
}

export function describePolicy(p: { mode: string; n?: number }): string {
  switch (p.mode) {
    case 'all':
      return t('policy.all');
    case 'last_n':
      return t('policy.lastN', { n: p.n ?? 0 });
    case 'days':
      return t('policy.days', { n: p.n ?? 0 });
    default:
      return t('policy.smart');
  }
}
