// Typed client of the RomSync API (see api/openapi.yaml).

import { randomId, sha256Hex } from './sha256';

export interface RetentionPolicy {
  mode: 'all' | 'last_n' | 'days' | 'smart';
  n?: number;
}

export interface User {
  id: number;
  username: string;
  role: 'admin' | 'user';
  created_at: string;
  disabled_at: string | null;
  retention_policy: RetentionPolicy;
}

export interface Invite {
  id: number;
  created_by: number;
  created_at: string;
  expires_at: string;
  used_by: number | null;
  used_by_username: string | null;
  used_at: string | null;
  status: 'pending' | 'used' | 'expired';
}

export interface Device {
  id: number;
  name: string;
  platform: string;
  created_at: string;
  last_seen_at: string | null;
  revoked_at: string | null;
  clock_skew_at: string | null;
}

export interface Version {
  id: number;
  game_code: string;
  sha256: string;
  size: number;
  saved_at: string;
  saved_at_reported: string | null;
  uploaded_at: string;
  device_id: number | null;
  device_name: string | null;
  emulator: string;
  base_version_id: number | null;
  is_active: boolean;
  conflict: boolean;
  pinned: boolean;
  note: string;
  /** Cut or chip size change made by this upload. */
  size_event: { type: 'trimmed' | 'shrunk' | 'forced'; from: number } | null;
}

export interface Game {
  code: string;
  title: string;
  region: string | null;
  chip_size: number | null;
  first_seen_at: string;
  retention_policy: RetentionPolicy | null;
  version_count: number;
  conflict: boolean;
  active_version: Version | null;
}

export interface UploadResult {
  version: Version;
  created: boolean;
  active: boolean;
  conflict: boolean;
}

export type Profile = 'raw' | 'desmume' | 'flashcard';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/** Called when a request fails with 401, so the app can return to the login page. */
let onUnauthorized: (() => void) | null = null;
export function setUnauthorizedHandler(fn: () => void) {
  onUnauthorized = fn;
}

const MESSAGES: Record<string, string> = {
  unauthorized: 'Session expirée ou identifiants incorrects.',
  forbidden: 'Action non autorisée.',
  not_found: 'Introuvable.',
  rate_limited: 'Trop de tentatives : réessaie dans une minute.',
  too_large: 'Fichier trop volumineux.',
  hash_mismatch: 'Le fichier a été altéré pendant l’envoi.',
  expired: 'Ce lien ou ce code a expiré ou a déjà été utilisé.',
  already_setup: 'Le serveur est déjà configuré.',
};

async function request<T>(method: string, path: string, init: { json?: unknown; body?: BodyInit; headers?: Record<string, string> } = {}): Promise<T> {
  const headers: Record<string, string> = { ...init.headers };
  let body = init.body;
  if (init.json !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(init.json);
  }
  const res = await fetch(`/api/v1${path}`, { method, headers, body, credentials: 'same-origin' });
  if (!res.ok) {
    let code = 'internal';
    let message = `Erreur ${res.status}`;
    try {
      const err = (await res.json()).error;
      code = err.code;
      message = MESSAGES[code] ?? err.message;
    } catch {
      /* not JSON */
    }
    if (res.status === 401 && path !== '/auth/login' && onUnauthorized) onUnauthorized();
    throw new ApiError(res.status, code, message);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

const enc = encodeURIComponent;

export const api = {
  setupNeeded: () => request<{ needed: boolean }>('GET', '/setup').then((r) => r.needed),
  setup: (username: string, password: string) =>
    request<{ user: User }>('POST', '/setup', { json: { username, password } }).then((r) => r.user),
  login: (username: string, password: string) =>
    request<{ user: User }>('POST', '/auth/login', { json: { username, password } }).then((r) => r.user),
  logout: () => request<void>('POST', '/auth/logout'),
  me: () => request<{ user: User }>('GET', '/me').then((r) => r.user),
  updateMe: (patch: { retention_policy?: RetentionPolicy; current_password?: string; new_password?: string }) =>
    request<{ user: User }>('PATCH', '/me', { json: patch }).then((r) => r.user),

  users: () => request<{ users: User[] }>('GET', '/users').then((r) => r.users),
  updateUser: (id: number, patch: { disabled?: boolean; password?: string }) =>
    request<{ user: User }>('PATCH', `/users/${id}`, { json: patch }).then((r) => r.user),
  invites: () => request<{ invites: Invite[] }>('GET', '/invites').then((r) => r.invites),
  createInvite: (expiresInDays: number) =>
    request<{ invite: Invite; token: string }>('POST', '/invites', { json: { expires_in_days: expiresInDays } }),
  acceptInvite: (token: string, username: string, password: string) =>
    request<{ user: User }>('POST', `/invites/${enc(token)}/accept`, { json: { username, password } }).then((r) => r.user),

  createPairCode: () => request<{ code: string; expires_at: string }>('POST', '/pair-codes'),
  devices: () => request<{ devices: Device[] }>('GET', '/devices').then((r) => r.devices),
  revokeDevice: (id: number) => request<void>('DELETE', `/devices/${id}`),

  games: () => request<{ games: Game[] }>('GET', '/games').then((r) => r.games),
  updateGame: (code: string, patch: { title?: string; retention_policy?: RetentionPolicy | null }) =>
    request<{ game: Game }>('PATCH', `/games/${enc(code)}`, { json: patch }).then((r) => r.game),
  versions: (code: string, before?: number, limit = 50) =>
    request<{ versions: Version[]; next_before: number | null }>(
      'GET',
      `/games/${enc(code)}/versions?limit=${limit}${before ? `&before=${before}` : ''}`,
    ),
  /** Latest release known by the server's relay (503 when unknown or disabled). */
  updates: () =>
    request<{ server_version: string; latest: { version: string; notes: string; published_at: string; url: string } }>(
      'GET',
      '/updates',
    ),
  activate: (id: number) => request<{ version: Version }>('POST', `/versions/${id}/activate`).then((r) => r.version),
  updateVersion: (id: number, patch: { pinned?: boolean; note?: string }) =>
    request<{ version: Version }>('PATCH', `/versions/${id}`, { json: patch }).then((r) => r.version),
  deleteVersion: (id: number) => request<void>('DELETE', `/versions/${id}`),

  /** Uploads a save file from the web interface. */
  async upload(opts: {
    code: string;
    file: Uint8Array;
    profile: Profile;
    savedAt: Date;
    baseVersionId: number | null;
    title?: string;
    forceSize?: boolean;
    uploadId?: string;
  }): Promise<UploadResult> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/octet-stream',
      'X-Upload-Id': opts.uploadId ?? randomId(),
      'X-Saved-At': opts.savedAt.toISOString(),
      'X-Base-Version': opts.baseVersionId ? String(opts.baseVersionId) : '',
      'X-Emulator': 'web-import',
      'X-Content-SHA256': await sha256Hex(opts.file),
    };
    // Browsers only send Latin-1 header values: the title is percent-encoded.
    if (opts.title) headers['X-Game-Title'] = encodeURIComponent(opts.title);
    if (opts.forceSize) headers['X-Force-Size'] = 'true';
    return request<UploadResult>('POST', `/games/${enc(opts.code)}/versions?profile=${opts.profile}`, {
      body: opts.file as Uint8Array<ArrayBuffer>,
      headers,
    });
  },

  contentURL: (id: number) => `/api/v1/versions/${id}/content`,
  exportURL: (id: number, profile: Profile) => `/api/v1/versions/${id}/export?profile=${profile}`,
};
