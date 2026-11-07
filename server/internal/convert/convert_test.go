package convert

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// pattern returns n bytes of non-trivial data.
func pattern(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(i*31 + i/251)
	}
	return b
}

func TestFooterLengthMatchesDeSmuMESources(t *testing.T) {
	if len(DeSmuMEFooterText) != 82 || DeSmuMEFooterLength != 122 {
		t.Fatalf("footer text %d bytes, footer %d bytes", len(DeSmuMEFooterText), DeSmuMEFooterLength)
	}
}

// The testdata footers were cut from .dsv files written by DeSmuME itself
// (a 512 KiB flash save). They hold sizes and the cookie, no game data.
func readFooter(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	if len(b) != DeSmuMEFooterLength {
		t.Fatalf("%s: %d bytes", name, len(b))
	}
	return b
}

func TestDeSmuMERoundTripWithRealFooter(t *testing.T) {
	raw := pattern(512 << 10)
	real := append(bytes.Clone(raw), readFooter(t, "desmume_footer_512k.bin")...)

	got, err := DeSmuME{}.Decode(real)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, raw) {
		t.Fatal("decoded data differs from the original")
	}
	// Our footer is byte-identical to the one DeSmuME wrote.
	if enc := (DeSmuME{}).Encode(got); !bytes.Equal(enc, real) {
		t.Fatalf("encoded footer differs from DeSmuME's:\n got %x\nwant %x",
			enc[len(enc)-DeSmuMEFooterLength:], real[len(real)-DeSmuMEFooterLength:])
	}
}

func TestDeSmuMEDecodeIgnoresTypeField(t *testing.T) {
	// DeSmuME sometimes leaves the type at 0 (autodetect).
	footer := readFooter(t, "desmume_footer_512k_type0.bin")
	if binary.LittleEndian.Uint32(footer[82+8:]) != 0 {
		t.Fatal("fixture should have type 0")
	}
	raw := pattern(512 << 10)
	got, err := DeSmuME{}.Decode(append(bytes.Clone(raw), footer...))
	if err != nil || !bytes.Equal(got, raw) {
		t.Fatalf("decode failed: %v", err)
	}
}

func TestDeSmuMERoundTripAllChipSizes(t *testing.T) {
	for _, n := range []int{512, 8 << 10, 32 << 10, 64 << 10, 128 << 10, 256 << 10, 512 << 10, 1 << 20, 8 << 20} {
		raw := pattern(n)
		enc := DeSmuME{}.Encode(raw)
		if len(enc) != n+122 {
			t.Fatalf("%d: encoded length %d", n, len(enc))
		}
		dec, err := DeSmuME{}.Decode(enc)
		if err != nil || !bytes.Equal(dec, raw) {
			t.Fatalf("%d: round trip failed: %v", n, err)
		}
	}
	// Fields for a 128 KiB save, which has no entry in DeSmuME's table.
	enc := DeSmuME{}.Encode(pattern(128 << 10))
	f := enc[len(enc)-122+82:]
	if typ, addr := binary.LittleEndian.Uint32(f[8:]), binary.LittleEndian.Uint32(f[12:]); typ != 0 || addr != 3 {
		t.Fatalf("128 KiB: type %d addr_size %d", typ, addr)
	}
	enc = DeSmuME{}.Encode(pattern(512))
	f = enc[len(enc)-122+82:]
	if typ, addr := binary.LittleEndian.Uint32(f[8:]), binary.LittleEndian.Uint32(f[12:]); typ != 1 || addr != 1 {
		t.Fatalf("512 B: type %d addr_size %d", typ, addr)
	}
}

func TestDeSmuMEDecodeErrors(t *testing.T) {
	valid := DeSmuME{}.Encode(pattern(512))

	if _, err := (DeSmuME{}).Decode(pattern(512)); err != ErrNotDeSmuME {
		t.Fatalf("raw file: %v", err)
	}
	if _, err := (DeSmuME{}).Decode(valid[len(valid)-100:]); err != ErrNotDeSmuME {
		t.Fatalf("truncated file: %v", err)
	}
	badVersion := bytes.Clone(valid)
	binary.LittleEndian.PutUint32(badVersion[len(badVersion)-16-4:], 1)
	if _, err := (DeSmuME{}).Decode(badVersion); err == nil {
		t.Fatal("version 1 must be rejected")
	}
	badSize := append(pattern(10), valid...)
	if _, err := (DeSmuME{}).Decode(badSize); err == nil {
		t.Fatal("padSize mismatch must be rejected")
	}
}

// TestDeSmuMERealFile checks a complete .dsv file when one is provided:
//
//	ROMSYNC_TEST_DSV=/path/to/game.dsv go test ./internal/convert
func TestDeSmuMERealFile(t *testing.T) {
	path := os.Getenv("ROMSYNC_TEST_DSV")
	if path == "" {
		t.Skip("set ROMSYNC_TEST_DSV to check a real .dsv file")
	}
	file, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := DeSmuME{}.Decode(file)
	if err != nil {
		t.Fatal(err)
	}
	enc := DeSmuME{}.Encode(raw)
	if len(enc) != len(file) {
		t.Fatalf("length %d, want %d", len(enc), len(file))
	}
	// Everything must match except the type field, which DeSmuME may leave at 0.
	typeOff := len(file) - 122 + 82 + 8
	for i := range file {
		if i >= typeOff && i < typeOff+4 {
			continue
		}
		if enc[i] != file[i] {
			t.Fatalf("byte %d differs: %#x vs %#x", i, enc[i], file[i])
		}
	}
}

func TestRaw(t *testing.T) {
	raw := pattern(8 << 10)
	if !bytes.Equal(Raw{}.Encode(raw), raw) {
		t.Fatal("raw encode must be the identity")
	}
	if dec, _ := (Raw{}).Decode(raw); !bytes.Equal(dec, raw) {
		t.Fatal("raw decode must be the identity")
	}
}

// profileFile is the declarative profile format of profiles/*.json.
type profileFile struct {
	ID        string `json:"id"`
	Extension string `json:"extension"`
	Footer    *struct {
		Length int    `json:"length"`
		Prefix string `json:"prefix"`
		Cookie string `json:"cookie"`
	} `json:"footer"`
}

func TestProfilesMatchCode(t *testing.T) {
	dir := filepath.Join("..", "..", "..", "profiles")
	for _, id := range IDs() {
		b, err := os.ReadFile(filepath.Join(dir, id+".json"))
		if err != nil {
			t.Fatalf("profile %s: %v", id, err)
		}
		var pf profileFile
		if err := json.Unmarshal(b, &pf); err != nil {
			t.Fatalf("profile %s: %v", id, err)
		}
		p, _ := Get(id)
		if pf.ID != p.ID() || pf.Extension != p.Extension() {
			t.Errorf("profile %s: id/extension %s %s vs %s %s", id, pf.ID, pf.Extension, p.ID(), p.Extension())
		}
		switch id {
		case "raw":
			if pf.Footer != nil {
				t.Errorf("raw must not declare a footer")
			}
		case "desmume":
			if pf.Footer == nil || pf.Footer.Length != DeSmuMEFooterLength ||
				pf.Footer.Prefix != DeSmuMEFooterText || pf.Footer.Cookie != DeSmuMECookie {
				t.Errorf("desmume footer differs from the code: %+v", pf.Footer)
			}
		}
	}
}
