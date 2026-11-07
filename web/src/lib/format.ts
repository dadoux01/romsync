const dateFmt = new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short' });

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  return dateFmt.format(new Date(iso));
}

const rtf = new Intl.RelativeTimeFormat('fr', { numeric: 'auto' });

export function relativeDate(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return 'jamais';
  const diff = (new Date(iso).getTime() - now) / 1000;
  const abs = Math.abs(diff);
  if (abs < 60) return rtf.format(Math.round(diff), 'second');
  if (abs < 3600) return rtf.format(Math.round(diff / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(diff / 3600), 'hour');
  if (abs < 86400 * 30) return rtf.format(Math.round(diff / 86400), 'day');
  return formatDate(iso);
}

export function formatSize(bytes: number | null | undefined): string {
  if (bytes == null) return '—';
  if (bytes < 1024) return `${bytes} o`;
  if (bytes < 1024 * 1024) return `${+(bytes / 1024).toFixed(1)} Kio`;
  return `${+(bytes / 1024 / 1024).toFixed(1)} Mio`;
}

/** Describes the size event of a version, for the history. */
export function describeSizeEvent(e: { type: string; from: number }, size: number): string {
  switch (e.type) {
    case 'trimmed':
      return `Reçue en ${formatSize(e.from)} : le remplissage a été coupé à ${formatSize(size)}.`;
    case 'shrunk':
      return `Taille de save du jeu passée de ${formatSize(e.from)} à ${formatSize(size)} (le reste de la version active n’était que du remplissage).`;
    case 'forced':
      return `Taille forcée depuis le site (avant : ${formatSize(e.from)}).`;
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
      return 'tout garder';
    case 'last_n':
      return `les ${p.n} dernières versions`;
    case 'days':
      return `les versions de moins de ${p.n} jours`;
    default:
      return 'intelligente';
  }
}
