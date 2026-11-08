/** Release versions ("0.5.0", "v0.5.0-rc1"), as server/internal/updates. */
export interface Version {
  major: number;
  minor: number;
  patch: number;
  pre: string;
}

export function parseVersion(s: string): Version | null {
  const m = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.]+))?$/.exec(s.trim());
  if (!m) return null;
  return { major: +m[1], minor: +m[2], patch: +m[3], pre: m[4] ?? '' };
}

/** -1, 0 or 1; a pre-release is older than its release. */
export function compareVersions(a: Version, b: Version): number {
  for (const [x, y] of [
    [a.major, b.major],
    [a.minor, b.minor],
    [a.patch, b.patch],
  ]) {
    if (x !== y) return x < y ? -1 : 1;
  }
  if (a.pre === b.pre) return 0;
  if (a.pre === '') return 1;
  if (b.pre === '') return -1;
  return a.pre < b.pre ? -1 : 1;
}

/** Whether latest is newer than current; false when either is not a version ("dev"). */
export function isNewer(latest: string, current: string): boolean {
  const l = parseVersion(latest);
  const c = parseVersion(current);
  return l !== null && c !== null && compareVersions(l, c) > 0;
}
