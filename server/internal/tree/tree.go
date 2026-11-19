// Package tree builds the canonical archive of a save made of a folder
// (docs/SPEC.md, "Saves en dossier"): a deterministic ustar archive, so that
// the same content always gives the same bytes and SHA-256 on every client.
// The test vectors in testdata/tree are shared with romsync_core and the C
// core.
package tree

import (
	"archive/tar"
	"bytes"
	"errors"
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Entry is a file or a folder of a save. A folder's path ends with "/".
type Entry struct {
	Path string
	Data []byte
}

// IsDir reports whether e is a folder.
func (e Entry) IsDir() bool { return strings.HasSuffix(e.Path, "/") }

// ErrInvalid is wrapped by the errors of invalid archives and entries.
var ErrInvalid = errors.New("tree: invalid save folder")

func invalid(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalid, fmt.Sprintf(format, args...))
}

// cleanPath checks a relative path and returns it without "./" and with a
// final "/" for a folder.
func cleanPath(p string, dir bool) (string, error) {
	p = strings.TrimPrefix(p, "./")
	p = strings.TrimSuffix(p, "/")
	if p == "" || strings.HasPrefix(p, "/") || !utf8.ValidString(p) || strings.ContainsRune(p, 0) {
		return "", invalid("path %q", p)
	}
	for _, part := range strings.Split(p, "/") {
		if part == "" || part == "." || part == ".." {
			return "", invalid("path %q", p)
		}
	}
	if dir {
		p += "/"
	}
	return p, nil
}

// Canonical returns the canonical archive of entries, in any order. The
// parent folders of every entry are added when missing.
func Canonical(entries []Entry) ([]byte, error) {
	byPath := map[string]Entry{}
	add := func(e Entry) error {
		if prev, ok := byPath[strings.TrimSuffix(e.Path, "/")]; ok {
			if prev.IsDir() && e.IsDir() {
				return nil
			}
			return invalid("duplicate path %q", e.Path)
		}
		byPath[strings.TrimSuffix(e.Path, "/")] = e
		return nil
	}
	for _, e := range entries {
		p, err := cleanPath(e.Path, e.IsDir())
		if err != nil {
			return nil, err
		}
		if strings.HasSuffix(p, "/") && len(e.Data) > 0 {
			return nil, invalid("folder %q with content", p)
		}
		if err := add(Entry{Path: p, Data: e.Data}); err != nil {
			return nil, err
		}
		parts := strings.Split(strings.TrimSuffix(p, "/"), "/")
		for i := 1; i < len(parts); i++ {
			if err := add(Entry{Path: strings.Join(parts[:i], "/") + "/"}); err != nil {
				return nil, err
			}
		}
	}
	sorted := make([]Entry, 0, len(byPath))
	for _, e := range byPath {
		sorted = append(sorted, e)
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Path < sorted[j].Path })

	var out bytes.Buffer
	for _, e := range sorted {
		h, err := header(e.Path, e.IsDir(), len(e.Data))
		if err != nil {
			return nil, err
		}
		out.Write(h)
		out.Write(e.Data)
		out.Write(make([]byte, (512-len(e.Data)%512)%512))
	}
	out.Write(make([]byte, 1024))
	return out.Bytes(), nil
}

func octal(dst []byte, n int64) {
	s := strconv.FormatInt(n, 8)
	copy(dst, strings.Repeat("0", len(dst)-1-len(s))+s)
}

// header is the 512-byte ustar header of the specification.
func header(path string, dir bool, size int) ([]byte, error) {
	name, prefix := path, ""
	if len(path) > 100 {
		cut := -1
		for i := len(path) - 1; i >= 0; i-- {
			if path[i] == '/' && i <= 155 && len(path)-i-1 <= 100 && len(path)-i-1 > 0 {
				cut = i
				break
			}
		}
		if cut < 0 {
			return nil, invalid("path too long %q", path)
		}
		prefix, name = path[:cut], path[cut+1:]
	}
	h := make([]byte, 512)
	copy(h[0:100], name)
	mode, typ, n := int64(0o644), byte('0'), int64(size)
	if dir {
		mode, typ, n = 0o755, '5', 0
	}
	octal(h[100:108], mode)
	octal(h[108:116], 0)
	octal(h[116:124], 0)
	octal(h[124:136], n)
	octal(h[136:148], 0)
	copy(h[148:156], "        ")
	h[156] = typ
	copy(h[257:263], "ustar\x00")
	copy(h[263:265], "00")
	copy(h[345:500], prefix)
	sum := 0
	for _, b := range h {
		sum += int(b)
	}
	s := strconv.FormatInt(int64(sum), 8)
	copy(h[148:156], strings.Repeat("0", 6-len(s))+s+"\x00 ")
	return h, nil
}

// Canonicalize reads any tar archive (ustar, PAX or GNU) and returns its
// canonical form. Links and special files are refused.
func Canonicalize(archive []byte) ([]byte, error) {
	r := tar.NewReader(bytes.NewReader(archive))
	var entries []Entry
	for {
		h, err := r.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, invalid("%v", err)
		}
		switch h.Typeflag {
		case tar.TypeDir:
			entries = append(entries, Entry{Path: strings.TrimSuffix(h.Name, "/") + "/"})
		case tar.TypeReg, tar.TypeRegA: //nolint:staticcheck // old archives use TypeRegA
			data, err := io.ReadAll(r)
			if err != nil {
				return nil, invalid("%v", err)
			}
			entries = append(entries, Entry{Path: strings.TrimSuffix(h.Name, "/"), Data: data})
		default:
			return nil, invalid("%q is not a file nor a folder", h.Name)
		}
	}
	return Canonical(entries)
}
