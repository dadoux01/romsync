// Package blobs stores save contents as files named by their SHA-256:
// <root>/<first 2 hex chars>/<sha256>. Identical contents are stored once.
package blobs

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sync"
)

var hashRE = regexp.MustCompile(`^[0-9a-f]{64}$`)

// ValidHash reports whether h is a lowercase hex SHA-256.
func ValidHash(h string) bool { return hashRE.MatchString(h) }

// Sum returns the lowercase hex SHA-256 of data.
func Sum(data []byte) string {
	s := sha256.Sum256(data)
	return hex.EncodeToString(s[:])
}

// Store is a content-addressed file store.
//
// Writers that are about to reference a blob from the database hold a shared
// lock (Use) from the write until the commit; the garbage collector holds the
// exclusive lock (Exclusive) while it checks references and deletes files, so
// it can never delete a blob that is about to be referenced.
type Store struct {
	root string
	mu   sync.RWMutex
}

// New creates the store rooted at dir (typically <data>/blobs).
func New(dir string) (*Store, error) {
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o750); err != nil {
		return nil, err
	}
	return &Store{root: dir}, nil
}

// Path returns the file path of a blob.
func (s *Store) Path(hash string) string {
	return filepath.Join(s.root, hash[:2], hash)
}

// Use runs fn under the shared lock.
func (s *Store) Use(fn func() error) error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return fn()
}

// Exclusive runs fn under the exclusive lock.
func (s *Store) Exclusive(fn func() error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return fn()
}

// Put stores data and returns its hash; an existing blob is not rewritten.
// The write goes through a temporary file and a rename, so a blob file is
// always complete.
func (s *Store) Put(data []byte) (string, error) {
	hash := Sum(data)
	final := s.Path(hash)
	if _, err := os.Stat(final); err == nil {
		return hash, nil
	}
	if err := os.MkdirAll(filepath.Dir(final), 0o750); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(filepath.Join(s.root, "tmp"), "blob-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Rename(tmp.Name(), final); err != nil {
		return "", err
	}
	return hash, nil
}

// Open opens a blob for reading.
func (s *Store) Open(hash string) (*os.File, error) {
	if !ValidHash(hash) {
		return nil, fmt.Errorf("blobs: invalid hash %q", hash)
	}
	return os.Open(s.Path(hash))
}

// Read returns the content of a blob.
func (s *Store) Read(hash string) ([]byte, error) {
	if !ValidHash(hash) {
		return nil, fmt.Errorf("blobs: invalid hash %q", hash)
	}
	return os.ReadFile(s.Path(hash))
}

// Remove deletes a blob; a missing blob is not an error. Callers must hold
// the exclusive lock and have checked that nothing references it.
func (s *Store) Remove(hash string) error {
	if !ValidHash(hash) {
		return fmt.Errorf("blobs: invalid hash %q", hash)
	}
	err := os.Remove(s.Path(hash))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	return err
}
