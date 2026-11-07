package blobs

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestPutDeduplicatesAndUsesShardedPaths(t *testing.T) {
	dir := t.TempDir()
	s, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	data := []byte("save data")
	h1, err := s.Put(data)
	if err != nil {
		t.Fatal(err)
	}
	if h1 != Sum(data) || !ValidHash(h1) {
		t.Fatalf("unexpected hash %s", h1)
	}
	want := filepath.Join(dir, h1[:2], h1)
	if s.Path(h1) != want {
		t.Fatalf("path %s, want %s", s.Path(h1), want)
	}
	st1, err := os.Stat(want)
	if err != nil {
		t.Fatal(err)
	}

	h2, err := s.Put(data)
	if err != nil || h2 != h1 {
		t.Fatalf("second put: %s %v", h2, err)
	}
	st2, _ := os.Stat(want)
	if !st1.ModTime().Equal(st2.ModTime()) {
		t.Fatal("an existing blob must not be rewritten")
	}

	got, err := s.Read(h1)
	if err != nil || !bytes.Equal(got, data) {
		t.Fatalf("read back %q %v", got, err)
	}
	if entries, _ := os.ReadDir(filepath.Join(dir, "tmp")); len(entries) != 0 {
		t.Fatal("temporary files must be cleaned up")
	}

	if err := s.Remove(h1); err != nil {
		t.Fatal(err)
	}
	if err := s.Remove(h1); err != nil {
		t.Fatal("removing a missing blob must not fail")
	}
	if _, err := s.Read(h1); err == nil {
		t.Fatal("blob must be gone")
	}
}

func TestRejectsInvalidHashes(t *testing.T) {
	s, _ := New(t.TempDir())
	for _, h := range []string{"", "../etc/passwd", "ABCDEF"} {
		if _, err := s.Read(h); err == nil {
			t.Errorf("Read(%q) must fail", h)
		}
		if err := s.Remove(h); err == nil {
			t.Errorf("Remove(%q) must fail", h)
		}
	}
}
