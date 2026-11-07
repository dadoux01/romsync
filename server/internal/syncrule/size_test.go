package syncrule

import (
	"bytes"
	"errors"
	"testing"
)

const (
	k64  = 64 << 10
	k512 = 512 << 10
)

// game returns n bytes of real (non-padding) save data.
func game(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(i*7 + 1)
	}
	return b
}

// padded returns data followed by fill up to total bytes.
func padded(data []byte, total int, fill byte) []byte {
	return append(bytes.Clone(data), bytes.Repeat([]byte{fill}, total-len(data))...)
}

func noActive() ([]byte, error) { return nil, nil }

func activeIs(b []byte) func() ([]byte, error) { return func() ([]byte, error) { return b, nil } }

func TestIsValidChipSize(t *testing.T) {
	for _, n := range []int64{512, 8192, 32768, 65536, 524288, 1 << 20, 8 << 20, 64 << 20} {
		if !IsValidChipSize(n) {
			t.Errorf("%d must be valid", n)
		}
	}
	for _, n := range []int64{0, 511, 40000, 100000, 3 << 20} {
		if IsValidChipSize(n) {
			t.Errorf("%d must be invalid", n)
		}
	}
}

func TestIsPadding(t *testing.T) {
	for _, c := range []struct {
		b    []byte
		want bool
	}{
		{nil, false},
		{[]byte{0xFF, 0xFF}, true},
		{[]byte{0, 0, 0}, true},
		{[]byte{0xFF, 0x00}, false}, // mixed fill is not padding
		{[]byte{0x12, 0x12}, false},
	} {
		if got := IsPadding(c.b); got != c.want {
			t.Errorf("IsPadding(%x) = %v", c.b, got)
		}
	}
}

func TestFirstSaveSetsChipSize(t *testing.T) {
	r, err := ResolveSize(game(k512), 0, noActive, false)
	if err != nil || r.ChipSize != k512 || r.Event != nil || len(r.Data) != k512 {
		t.Fatalf("got %+v %v", r, err)
	}
}

// A 512 KiB save whose second half is still blank is a valid save: it must
// never be cut without a smaller upload.
func TestHalfBlankSaveIsNeverCut(t *testing.T) {
	half := padded(game(k512/2), k512, 0xFF)
	r, err := ResolveSize(half, 0, noActive, false)
	if err != nil || r.ChipSize != k512 || len(r.Data) != k512 || r.Event != nil {
		t.Fatalf("first upload: %+v %v", r, err)
	}
	r, err = ResolveSize(half, k512, activeIs(half), false)
	if err != nil || r.ChipSize != k512 || len(r.Data) != k512 || r.Event != nil {
		t.Fatalf("same-size upload: %+v %v", r, err)
	}
}

func TestLargerUploadWithPaddingIsTrimmed(t *testing.T) {
	for _, fill := range []byte{0xFF, 0x00} {
		data := game(k64)
		r, err := ResolveSize(padded(data, k512, fill), k64, nil, false)
		if err != nil || !bytes.Equal(r.Data, data) || r.ChipSize != k64 ||
			r.Event == nil || *r.Event != (SizeEvent{Type: SizeTrimmed, From: k512}) {
			t.Fatalf("fill %#x: %+v %v", fill, r, err)
		}
	}
}

func TestLargerUploadWithDataIsRefused(t *testing.T) {
	if _, err := ResolveSize(game(k512), k64, nil, false); !errors.Is(err, ErrSizeMismatch) {
		t.Fatalf("got %v", err)
	}
	r, err := ResolveSize(game(k512), k64, nil, true)
	if err != nil || r.ChipSize != k512 || *r.Event != (SizeEvent{Type: SizeForced, From: k64}) {
		t.Fatalf("forced: %+v %v", r, err)
	}
}

func TestSmallerUpload(t *testing.T) {
	// The active version's excess is padding: the chip size shrinks.
	active := padded(game(k64), k512, 0xFF)
	r, err := ResolveSize(game(k64), k512, activeIs(active), false)
	if err != nil || r.ChipSize != k64 || *r.Event != (SizeEvent{Type: SizeShrunk, From: k512}) {
		t.Fatalf("got %+v %v", r, err)
	}
	// The active version has data beyond the new size: refused.
	if _, err := ResolveSize(game(k64), k512, activeIs(game(k512)), false); !errors.Is(err, ErrSizeMismatch) {
		t.Fatalf("got %v", err)
	}
	// No active version yet (size from the database): accepted when the
	// new size is a real chip size, and traced.
	r, err = ResolveSize(game(32<<10), k64, noActive, false)
	if err != nil || r.ChipSize != 32<<10 || *r.Event != (SizeEvent{Type: SizeShrunk, From: k64}) {
		t.Fatalf("got %+v %v", r, err)
	}
	if _, err := ResolveSize(game(40000), k64, noActive, false); !errors.Is(err, ErrSizeMismatch) {
		t.Fatalf("40000 bytes is not a chip size: %v", err)
	}
}

// DSTT (512 KiB file, padded) then melonDS (64 KiB) converge to 64 KiB, and
// later DSTT uploads are trimmed.
func TestFlashcardThenEmulatorConverges(t *testing.T) {
	save := game(k64)
	dstt := padded(save, k512, 0xFF)

	r1, err := ResolveSize(dstt, 0, noActive, false)
	if err != nil || r1.ChipSize != k512 {
		t.Fatalf("DSTT first: %+v %v", r1, err)
	}
	r2, err := ResolveSize(game(k64), r1.ChipSize, activeIs(r1.Data), false)
	if err != nil || r2.ChipSize != k64 || r2.Event.Type != SizeShrunk {
		t.Fatalf("melonDS: %+v %v", r2, err)
	}
	r3, err := ResolveSize(dstt, r2.ChipSize, activeIs(r2.Data), false)
	if err != nil || r3.ChipSize != k64 || !bytes.Equal(r3.Data, save) || r3.Event.Type != SizeTrimmed {
		t.Fatalf("DSTT again: %+v %v", r3, err)
	}
}
