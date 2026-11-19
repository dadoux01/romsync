-- Console of each game (docs/SPEC.md, "Multi-consoles"). The games stored
-- before phase 7 are Nintendo DS games; for the others, the console is the
-- prefix of game_code ("gba:BPEF"), checked by the server.
ALTER TABLE games ADD COLUMN system TEXT NOT NULL DEFAULT 'nds';
CREATE INDEX games_user_system ON games (user_id, system);
