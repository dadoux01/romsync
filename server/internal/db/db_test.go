package db

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func TestOpenMigratesAndIsIdempotent(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "romsync.db")

	conn, err := Open(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	var tables int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'
		AND name IN ('users','sessions','invites','devices','games','save_versions','pair_codes')`).Scan(&tables); err != nil {
		t.Fatal(err)
	}
	if tables != 7 {
		t.Fatalf("expected 7 tables, got %d", tables)
	}
	conn.Close()

	// Re-opening must not re-apply migrations.
	conn, err = Open(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	var applied int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM schema_migrations`).Scan(&applied); err != nil {
		t.Fatal(err)
	}
	migrations, err := loadMigrations()
	if err != nil {
		t.Fatal(err)
	}
	if applied != len(migrations) || applied < 2 {
		t.Fatalf("expected %d applied migrations, got %d", len(migrations), applied)
	}
}

func TestTimeFormatIsSortable(t *testing.T) {
	a := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)
	b := a.Add(10 * time.Millisecond)
	if FormatTime(a) >= FormatTime(b) {
		t.Fatal("formatted times must sort chronologically")
	}
	got, err := ParseTime(FormatTime(b))
	if err != nil || !got.Equal(b) {
		t.Fatalf("round trip failed: %v %v", got, err)
	}
}
