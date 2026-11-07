// Minimal history-based router: the Go server serves index.html for every
// path outside /api, so client-side URLs survive a reload.

export const route = $state({ path: location.pathname, search: location.search });

export function navigate(to: string, replace = false) {
  const url = new URL(to, location.origin);
  if (url.pathname === route.path && url.search === route.search) return;
  history[replace ? 'replaceState' : 'pushState'](null, '', url.pathname + url.search);
  route.path = url.pathname;
  route.search = url.search;
  window.scrollTo(0, 0);
}

addEventListener('popstate', () => {
  route.path = location.pathname;
  route.search = location.search;
});

// Intercept clicks on internal links.
addEventListener('click', (e) => {
  if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  const a = (e.target as Element | null)?.closest?.('a');
  if (!a || a.target || a.hasAttribute('download') || a.origin !== location.origin) return;
  if (a.pathname.startsWith('/api/')) return;
  e.preventDefault();
  navigate(a.pathname + a.search);
});

/** Matches a path against a pattern like /games/:code and returns its params. */
export function match(pattern: string, path: string): Record<string, string> | null {
  const p = pattern.split('/');
  const s = path.replace(/\/+$/, '').split('/');
  if (p.length !== s.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < p.length; i++) {
    if (p[i].startsWith(':')) params[p[i].slice(1)] = decodeURIComponent(s[i]);
    else if (p[i] !== s[i]) return null;
  }
  return params;
}
