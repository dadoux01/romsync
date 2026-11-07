-- RomSync initial schema (see docs/SPEC.md, "Modèle de données").
-- Dates are UTC strings in the fixed-width format 2006-01-02T15:04:05.000Z.

CREATE TABLE users (
    id               INTEGER PRIMARY KEY,
    username         TEXT    NOT NULL UNIQUE COLLATE NOCASE,
    password_hash    TEXT    NOT NULL,
    role             TEXT    NOT NULL CHECK (role IN ('admin', 'user')),
    created_at       TEXT    NOT NULL,
    disabled_at      TEXT,
    retention_policy TEXT    NOT NULL DEFAULT '{"mode":"smart"}'
);

CREATE TABLE sessions (
    token_hash TEXT    PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TEXT    NOT NULL,
    expires_at TEXT    NOT NULL
);
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE invites (
    id         INTEGER PRIMARY KEY,
    token_hash TEXT    NOT NULL UNIQUE,
    created_by INTEGER NOT NULL REFERENCES users (id),
    created_at TEXT    NOT NULL,
    expires_at TEXT    NOT NULL,
    used_by    INTEGER REFERENCES users (id),
    used_at    TEXT
);

CREATE TABLE devices (
    id            INTEGER PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name          TEXT    NOT NULL,
    platform      TEXT    NOT NULL,
    token_hash    TEXT    NOT NULL UNIQUE,
    created_at    TEXT    NOT NULL,
    last_seen_at  TEXT,
    revoked_at    TEXT,
    clock_skew_at TEXT
);
CREATE INDEX devices_user ON devices (user_id);

CREATE TABLE games (
    id               INTEGER PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    game_code        TEXT    NOT NULL,
    title            TEXT    NOT NULL,
    region           TEXT,
    chip_size        INTEGER,
    first_seen_at    TEXT    NOT NULL,
    retention_policy TEXT,
    UNIQUE (user_id, game_code)
);

CREATE TABLE save_versions (
    id                INTEGER PRIMARY KEY,
    game_id           INTEGER NOT NULL REFERENCES games (id) ON DELETE CASCADE,
    blob_hash         TEXT    NOT NULL,
    size              INTEGER NOT NULL,
    saved_at          TEXT    NOT NULL,
    saved_at_reported TEXT,
    uploaded_at       TEXT    NOT NULL,
    device_id         INTEGER REFERENCES devices (id) ON DELETE SET NULL,
    emulator          TEXT    NOT NULL DEFAULT '',
    base_version_id   INTEGER,
    upload_id         TEXT,
    is_active         INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
    conflict          INTEGER NOT NULL DEFAULT 0 CHECK (conflict IN (0, 1)),
    pinned            INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
    note              TEXT    NOT NULL DEFAULT ''
);
-- One active version per game at most.
CREATE UNIQUE INDEX save_versions_one_active ON save_versions (game_id) WHERE is_active = 1;
CREATE INDEX save_versions_game_saved ON save_versions (game_id, saved_at DESC, id DESC);
CREATE INDEX save_versions_blob ON save_versions (blob_hash);
-- Uniqueness per account is enforced by the server (the account is reached
-- through games.user_id); this index makes the lookup cheap.
CREATE INDEX save_versions_upload ON save_versions (upload_id) WHERE upload_id IS NOT NULL;

CREATE TABLE pair_codes (
    code_hash  TEXT    PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    expires_at TEXT    NOT NULL,
    used_at    TEXT
);
