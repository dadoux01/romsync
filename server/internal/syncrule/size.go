package syncrule

import "errors"

// Size events recorded on a version (see docs/SPEC.md, "Taille réelle").
const (
	// SizeTrimmed: the upload was larger than the game's chip size and its
	// excess was only padding; it was cut to the chip size.
	SizeTrimmed = "trimmed"
	// SizeShrunk: the upload was smaller than the chip size and the excess of
	// the active version was only padding; the chip size became the upload's.
	SizeShrunk = "shrunk"
	// SizeForced: the size was forced from the web interface.
	SizeForced = "forced"
)

// ErrSizeMismatch is returned when no rule reconciles the sizes.
var ErrSizeMismatch = errors.New("size mismatch")

// SizeEvent records a cut or a chip size change. From is the received size
// for SizeTrimmed, and the previous chip size otherwise.
type SizeEvent struct {
	Type string
	From int64
}

// SizeResult is the outcome of ResolveSize.
type SizeResult struct {
	Data     []byte     // the data to store, possibly cut
	ChipSize int64      // the game's chip size after this upload
	Event    *SizeEvent // nil when nothing was cut or changed
}

// ValidChipSizes are the save sizes of DS cartridges: the sizes known to
// DeSmuME and melonDS (EEPROM, FRAM, flash and NAND).
var ValidChipSizes = []int64{
	512, 8 << 10, 32 << 10, 64 << 10, 128 << 10, 256 << 10, 512 << 10,
	1 << 20, 2 << 20, 4 << 20, 8 << 20, 16 << 20, 32 << 20, 64 << 20,
}

// IsValidChipSize reports whether n is the size of a DS save chip.
func IsValidChipSize(n int64) bool {
	for _, s := range ValidChipSizes {
		if s == n {
			return true
		}
	}
	return false
}

// IsPadding reports whether b is non-empty and made of a single 0xFF or 0x00
// byte value.
func IsPadding(b []byte) bool {
	if len(b) == 0 {
		return false
	}
	if b[0] != 0xFF && b[0] != 0x00 {
		return false
	}
	for _, c := range b {
		if c != b[0] {
			return false
		}
	}
	return true
}

// ResolveSize reconciles an upload with the game's chip size (0 when not
// known yet). active returns the content of the active version, or nil when
// the game has none; it is only called when the upload is smaller.
//
// A save is never cut on the sole basis of its padding: it is only cut down
// to a chip size that is already known.
func ResolveSize(data []byte, chip int64, active func() ([]byte, error), force bool) (SizeResult, error) {
	n := int64(len(data))
	switch {
	case chip == 0 || n == chip:
		return SizeResult{Data: data, ChipSize: n}, nil

	case n > chip:
		if IsPadding(data[chip:]) {
			return SizeResult{Data: data[:chip], ChipSize: chip, Event: &SizeEvent{Type: SizeTrimmed, From: n}}, nil
		}

	default: // n < chip
		act, err := active()
		if err != nil {
			return SizeResult{}, err
		}
		// Without an active version (chip size from the database, first
		// save), nothing can be lost by accepting the smaller size, provided
		// it is a real chip size.
		if (act == nil && IsValidChipSize(n)) || (act != nil && int64(len(act)) > n && IsPadding(act[n:])) {
			return SizeResult{Data: data, ChipSize: n, Event: &SizeEvent{Type: SizeShrunk, From: chip}}, nil
		}
	}
	if force {
		return SizeResult{Data: data, ChipSize: n, Event: &SizeEvent{Type: SizeForced, From: chip}}, nil
	}
	return SizeResult{}, ErrSizeMismatch
}
