package tree

import (
	"archive/tar"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

type vector struct {
	Entries []struct {
		Path       string `json:"path"`
		ContentHex string `json:"content_hex"`
	} `json:"entries"`
	SHA256 string `json:"sha256"`
}

func loadVector(t *testing.T, name string) ([]Entry, []byte, string) {
	t.Helper()
	dir := filepath.Join("..", "..", "..", "testdata", "tree")
	b, err := os.ReadFile(filepath.Join(dir, name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var v vector
	if err := json.Unmarshal(b, &v); err != nil {
		t.Fatal(err)
	}
	var entries []Entry
	for _, e := range v.Entries {
		data, _ := hex.DecodeString(e.ContentHex)
		entries = append(entries, Entry{Path: e.Path, Data: data})
	}
	want, err := os.ReadFile(filepath.Join(dir, name+".tar"))
	if err != nil {
		t.Fatal(err)
	}
	return entries, want, v.SHA256
}

func TestSharedVectors(t *testing.T) {
	for _, name := range []string{"empty", "simple", "long-path"} {
		entries, want, sum := loadVector(t, name)
		got, err := Canonical(entries)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if !bytes.Equal(got, want) {
			t.Errorf("%s: archive differs from the vector", name)
		}
		if h := sha256.Sum256(got); hex.EncodeToString(h[:]) != sum {
			t.Errorf("%s: sha256", name)
		}
		// Canonical archives are their own canonical form.
		again, err := Canonicalize(want)
		if err != nil || !bytes.Equal(again, want) {
			t.Errorf("%s: canonicalize changed a canonical archive (%v)", name, err)
		}
	}
}

func TestCanonicalizeAnyTar(t *testing.T) {
	// A tar made by another tool: GNU format, dates, owners, "./" prefix,
	// no folder entries.
	var buf bytes.Buffer
	w := tar.NewWriter(&buf)
	for _, f := range []struct{ name, data string }{{"./b/x.bin", "x"}, {"./a.bin", "a"}} {
		_ = w.WriteHeader(&tar.Header{Name: f.name, Mode: 0o600, Size: int64(len(f.data)), Uid: 1000, Uname: "me",
			Typeflag: tar.TypeReg, Format: tar.FormatGNU})
		_, _ = w.Write([]byte(f.data))
	}
	_ = w.Close()
	got, err := Canonicalize(buf.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	want, _ := Canonical([]Entry{{Path: "a.bin", Data: []byte("a")}, {Path: "b/"}, {Path: "b/x.bin", Data: []byte("x")}})
	if !bytes.Equal(got, want) {
		t.Fatal("not the canonical archive")
	}
}

func TestRefusals(t *testing.T) {
	for _, entries := range [][]Entry{
		{{Path: "/etc/passwd", Data: []byte("x")}},
		{{Path: "a/../b", Data: []byte("x")}},
		{{Path: "a"}, {Path: "a", Data: []byte("y")}},
		{{Path: "a", Data: []byte("x")}, {Path: "a/b", Data: []byte("y")}}, // "a" a file and a folder
		{{Path: "a/", Data: []byte("folder with data")}},
		{{Path: string(bytes.Repeat([]byte("x"), 120))}},
	} {
		if _, err := Canonical(entries); !errors.Is(err, ErrInvalid) {
			t.Errorf("%v must be refused, got %v", entries[0].Path, err)
		}
	}
	var buf bytes.Buffer
	w := tar.NewWriter(&buf)
	_ = w.WriteHeader(&tar.Header{Name: "link", Linkname: "/etc/passwd", Typeflag: tar.TypeSymlink})
	_ = w.Close()
	if _, err := Canonicalize(buf.Bytes()); !errors.Is(err, ErrInvalid) {
		t.Errorf("a link must be refused, got %v", err)
	}
	if _, err := Canonicalize([]byte("not a tar")); !errors.Is(err, ErrInvalid) {
		t.Errorf("garbage must be refused, got %v", err)
	}
}
