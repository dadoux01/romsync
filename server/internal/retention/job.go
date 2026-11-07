package retention

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/db"
)

// Job applies the retention policies and removes unreferenced blobs.
type Job struct {
	DB    *sql.DB
	Blobs *blobs.Store
	// BlobDir is the blob store root, scanned for unreferenced files.
	BlobDir string
	Now     func() time.Time
}

// Stats summarises a run.
type Stats struct {
	VersionsRemoved int
	BlobsRemoved    int
}

// Run applies the policies at startup, then every interval, until ctx ends.
func (j *Job) Run(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		st, err := j.RunOnce(ctx)
		if err != nil {
			slog.Error("retention run failed", "err", err)
		} else if st.VersionsRemoved > 0 || st.BlobsRemoved > 0 {
			slog.Info("retention applied", "versions_removed", st.VersionsRemoved, "blobs_removed", st.BlobsRemoved)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

type gamePolicy struct {
	id     int64
	policy Policy
}

// RunOnce applies every game's effective policy (its own, or its account's),
// removes unreferenced blobs and purges expired sessions and pairing codes.
func (j *Job) RunOnce(ctx context.Context) (Stats, error) {
	var st Stats
	now := j.Now()

	rows, err := j.DB.QueryContext(ctx, `SELECT g.id, COALESCE(g.retention_policy, u.retention_policy)
		FROM games g JOIN users u ON u.id = g.user_id`)
	if err != nil {
		return st, err
	}
	var games []gamePolicy
	for rows.Next() {
		var g gamePolicy
		var raw string
		if err := rows.Scan(&g.id, &raw); err != nil {
			rows.Close()
			return st, err
		}
		p, err := Parse(raw)
		if err != nil {
			slog.Warn("skipping game with an invalid retention policy", "game_id", g.id, "err", err)
			continue
		}
		g.policy = p
		games = append(games, g)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return st, err
	}

	for _, g := range games {
		n, err := j.applyGame(ctx, g, now)
		if err != nil {
			return st, fmt.Errorf("game %d: %w", g.id, err)
		}
		st.VersionsRemoved += n
	}

	st.BlobsRemoved, err = j.collectBlobs(ctx)
	if err != nil {
		return st, err
	}

	ts := db.FormatTime(now)
	if _, err := j.DB.ExecContext(ctx, `DELETE FROM sessions WHERE expires_at <= ?`, ts); err != nil {
		return st, err
	}
	if _, err := j.DB.ExecContext(ctx, `DELETE FROM pair_codes WHERE expires_at <= ?`, db.FormatTime(now.Add(-24*time.Hour))); err != nil {
		return st, err
	}
	return st, nil
}

func (j *Job) applyGame(ctx context.Context, g gamePolicy, now time.Time) (int, error) {
	if g.policy.Mode == ModeAll {
		return 0, nil
	}
	tx, err := j.DB.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx, `SELECT id, saved_at, is_active, pinned FROM save_versions WHERE game_id = ?`, g.id)
	if err != nil {
		return 0, err
	}
	var versions []Version
	for rows.Next() {
		var v Version
		var savedAt string
		if err := rows.Scan(&v.ID, &savedAt, &v.Active, &v.Pinned); err != nil {
			rows.Close()
			return 0, err
		}
		if v.SavedAt, err = db.ParseTime(savedAt); err != nil {
			rows.Close()
			return 0, err
		}
		versions = append(versions, v)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	remove := Select(versions, g.policy, now)
	for _, id := range remove {
		// The condition re-checks the protections inside the transaction.
		if _, err := tx.ExecContext(ctx, `DELETE FROM save_versions WHERE id = ? AND is_active = 0 AND pinned = 0`, id); err != nil {
			return 0, err
		}
	}
	return len(remove), tx.Commit()
}

// collectBlobs deletes every blob file that no version references. It holds
// the store's exclusive lock, so no upload can be between writing a blob and
// committing the version that references it.
func (j *Job) collectBlobs(ctx context.Context) (int, error) {
	removed := 0
	err := j.Blobs.Exclusive(func() error {
		rows, err := j.DB.QueryContext(ctx, `SELECT DISTINCT blob_hash FROM save_versions`)
		if err != nil {
			return err
		}
		referenced := map[string]bool{}
		for rows.Next() {
			var h string
			if err := rows.Scan(&h); err != nil {
				rows.Close()
				return err
			}
			referenced[h] = true
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}

		shards, err := os.ReadDir(j.BlobDir)
		if err != nil {
			return err
		}
		for _, shard := range shards {
			if !shard.IsDir() || len(shard.Name()) != 2 {
				continue // skips tmp/
			}
			files, err := os.ReadDir(filepath.Join(j.BlobDir, shard.Name()))
			if err != nil {
				return err
			}
			for _, f := range files {
				h := f.Name()
				if !blobs.ValidHash(h) || !strings.HasPrefix(h, shard.Name()) || referenced[h] {
					continue
				}
				if err := j.Blobs.Remove(h); err != nil {
					return err
				}
				removed++
			}
		}
		return nil
	})
	return removed, err
}
