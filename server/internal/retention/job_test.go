package retention

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/db"
)

type fixture struct {
	t     *testing.T
	db    *sql.DB
	blobs *blobs.Store
	dir   string
	job   *Job
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	dir := t.TempDir()
	conn, err := db.Open(context.Background(), filepath.Join(dir, "romsync.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	blobDir := filepath.Join(dir, "blobs")
	store, err := blobs.New(blobDir)
	if err != nil {
		t.Fatal(err)
	}
	f := &fixture{t: t, db: conn, blobs: store, dir: blobDir}
	f.job = &Job{DB: conn, Blobs: store, BlobDir: blobDir, Now: func() time.Time { return now }}
	return f
}

func (f *fixture) exec(q string, args ...any) int64 {
	f.t.Helper()
	res, err := f.db.Exec(q, args...)
	if err != nil {
		f.t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return id
}

func (f *fixture) user(policy string) int64 {
	return f.exec(`INSERT INTO users (username, password_hash, role, created_at, retention_policy) VALUES (?, 'x', 'user', ?, ?)`,
		"u"+time.Now().Format("150405.000000000"), db.FormatTime(now), policy)
}

func (f *fixture) game(userID int64, code string, policy *string) int64 {
	return f.exec(`INSERT INTO games (user_id, game_code, title, first_seen_at, retention_policy) VALUES (?, ?, ?, ?, ?)`,
		userID, code, code, db.FormatTime(now), policy)
}

// version stores content as a blob and adds a version saved age ago.
func (f *fixture) version(gameID int64, content string, age time.Duration, active, pinned bool) int64 {
	f.t.Helper()
	h, err := f.blobs.Put([]byte(content))
	if err != nil {
		f.t.Fatal(err)
	}
	return f.exec(`INSERT INTO save_versions (game_id, blob_hash, size, saved_at, uploaded_at, is_active, pinned)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, gameID, h, len(content), db.FormatTime(now.Add(-age)), db.FormatTime(now), active, pinned)
}

func (f *fixture) versionIDs(gameID int64) map[int64]bool {
	f.t.Helper()
	rows, err := f.db.Query(`SELECT id FROM save_versions WHERE game_id = ?`, gameID)
	if err != nil {
		f.t.Fatal(err)
	}
	defer rows.Close()
	ids := map[int64]bool{}
	for rows.Next() {
		var id int64
		rows.Scan(&id)
		ids[id] = true
	}
	return ids
}

func (f *fixture) blobExists(content string) bool {
	_, err := os.Stat(f.blobs.Path(blobs.Sum([]byte(content))))
	return err == nil
}

func TestJobAppliesEffectivePolicies(t *testing.T) {
	f := newFixture(t)
	u := f.user(`{"mode":"last_n","n":2}`)
	gInherit := f.game(u, "AAAA", nil)
	override := `{"mode":"all"}`
	gAll := f.game(u, "BBBB", &override)

	a1 := f.version(gInherit, "a1", 1*time.Hour, true, false)
	a2 := f.version(gInherit, "a2", 2*time.Hour, false, false)
	a3 := f.version(gInherit, "a3", 3*time.Hour, false, false)
	a4 := f.version(gInherit, "a4", 4*time.Hour, false, true) // pinned
	a5 := f.version(gInherit, "shared", 5*time.Hour, false, false)
	for i := 0; i < 5; i++ {
		f.version(gAll, "b"+string(rune('0'+i)), time.Duration(i)*time.Hour, i == 0, false)
	}
	f.version(gAll, "shared", 10*time.Hour, false, false)

	st, err := f.job.RunOnce(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	ids := f.versionIDs(gInherit)
	if !ids[a1] || !ids[a2] || ids[a3] || !ids[a4] || ids[a5] {
		t.Fatalf("unexpected remaining versions %v", ids)
	}
	if len(f.versionIDs(gAll)) != 6 {
		t.Fatal("the per-game 'all' override must keep everything")
	}
	if st.VersionsRemoved != 2 {
		t.Fatalf("removed %d versions", st.VersionsRemoved)
	}

	// a3's blob is gone; the blob shared with the other game stays.
	if f.blobExists("a3") {
		t.Fatal("unreferenced blob must be removed")
	}
	if !f.blobExists("shared") || !f.blobExists("a1") {
		t.Fatal("referenced blobs must be kept")
	}
	if st.BlobsRemoved != 1 {
		t.Fatalf("removed %d blobs", st.BlobsRemoved)
	}
}

func TestJobNeverRemovesActiveOrPinned(t *testing.T) {
	f := newFixture(t)
	u := f.user(`{"mode":"days","n":1}`)
	g := f.game(u, "AAAA", nil)
	active := f.version(g, "old-active", 400*24*time.Hour, true, false)
	pinned := f.version(g, "old-pinned", 300*24*time.Hour, false, true)
	other := f.version(g, "old", 200*24*time.Hour, false, false)

	if _, err := f.job.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	ids := f.versionIDs(g)
	if !ids[active] || !ids[pinned] || ids[other] {
		t.Fatalf("unexpected remaining versions %v", ids)
	}
}

func TestJobRemovesOrphanBlobsAndExpiredRows(t *testing.T) {
	f := newFixture(t)
	if _, err := f.blobs.Put([]byte("orphan")); err != nil {
		t.Fatal(err)
	}
	u := f.user(`{"mode":"smart"}`)
	f.exec(`INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES ('old', ?, ?, ?)`, u,
		db.FormatTime(now.Add(-40*24*time.Hour)), db.FormatTime(now.Add(-time.Hour)))
	f.exec(`INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES ('live', ?, ?, ?)`, u,
		db.FormatTime(now), db.FormatTime(now.Add(time.Hour)))

	st, err := f.job.RunOnce(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if st.BlobsRemoved != 1 || f.blobExists("orphan") {
		t.Fatal("orphan blob must be removed")
	}
	var n int
	f.db.QueryRow(`SELECT COUNT(*) FROM sessions`).Scan(&n)
	if n != 1 {
		t.Fatalf("expected 1 live session, got %d", n)
	}
}
