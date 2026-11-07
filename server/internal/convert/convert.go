// Package convert converts saves between the canonical raw format stored by
// the server and emulator formats. The declarative description of each
// profile lives in profiles/ at the repository root; TestProfilesMatchCode
// keeps both in sync.
package convert

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
)

// Profile converts a save to and from an emulator file format.
type Profile interface {
	// ID is the profile identifier used in the API (?profile=...).
	ID() string
	// Extension is the file extension, with its dot.
	Extension() string
	// Encode turns raw save data into the profile's file format.
	Encode(raw []byte) ([]byte, error)
	// Decode turns a file of the profile's format into raw save data.
	Decode(file []byte) ([]byte, error)
}

var profiles = map[string]Profile{
	"raw":       Raw{},
	"desmume":   DeSmuME{},
	"flashcard": Flashcard{Size: FlashcardSize},
}

// Get returns the profile with the given id.
func Get(id string) (Profile, bool) {
	p, ok := profiles[id]
	return p, ok
}

// IDs lists the available profiles.
func IDs() []string { return []string{"raw", "desmume", "flashcard"} }

// Raw is the canonical format: the content of the save chip, unchanged.
// It is what melonDS writes in its .sav files.
type Raw struct{}

func (Raw) ID() string                         { return "raw" }
func (Raw) Extension() string                  { return ".sav" }
func (Raw) Encode(raw []byte) ([]byte, error)  { return bytes.Clone(raw), nil }
func (Raw) Decode(file []byte) ([]byte, error) { return bytes.Clone(file), nil }

// DeSmuME footer layout, as written by BackupDevice::ensure() in
// desmume/src/mc.cpp and checked by BackupDevice::GetDSVFileInfo().
const (
	DeSmuMEFooterText   = "|<--Snip above here to create a raw sav by excluding this DeSmuME savedata footer:"
	DeSmuMECookie       = "|-DESMUME SAVE-|"
	DeSmuMEFooterLength = len(DeSmuMEFooterText) + 6*4 + len(DeSmuMECookie) // 122
)

// deSmuMESaveTypes lists the sizes of DeSmuME's save_types table, starting
// at index 1 (index 0 is "autodetect"). Only the first 12 entries can be
// matched by searchFileSaveType(), whose loop stops before MAX_SAVE_TYPES (13).
var deSmuMESaveTypes = []uint32{
	512,       // 1: EEPROM 4kbit
	8 << 10,   // 2: EEPROM 64kbit
	64 << 10,  // 3: EEPROM 512kbit
	32 << 10,  // 4: FRAM 256kbit
	256 << 10, // 5: FLASH 2Mbit
	512 << 10, // 6: FLASH 4Mbit
	1 << 20,   // 7: FLASH 8Mbit
	2 << 20,   // 8: FLASH 16Mbit
	4 << 20,   // 9: FLASH 32Mbit
	8 << 20,   // 10: FLASH 64Mbit
	16 << 20,  // 11: FLASH 128Mbit
	32 << 20,  // 12: FLASH 256Mbit
}

func deSmuMEType(size uint32) uint32 {
	for i, s := range deSmuMESaveTypes {
		if s == size {
			return uint32(i + 1) //nolint:gosec // i < 12
		}
	}
	return 0
}

func deSmuMEAddrSize(size uint32) uint32 {
	switch {
	case size <= 512:
		return 1
	case size <= 64<<10:
		return 2
	default:
		return 3
	}
}

// DeSmuME handles .dsv files: raw data followed by a 122-byte footer.
type DeSmuME struct{}

func (DeSmuME) ID() string        { return "desmume" }
func (DeSmuME) Extension() string { return ".dsv" }

// Encode appends the footer that DeSmuME writes for a save of this size.
// Saves are bounded by the upload limit, far below the 4 GiB a u32 holds.
func (DeSmuME) Encode(raw []byte) ([]byte, error) {
	n := uint32(len(raw)) //nolint:gosec // see above
	out := make([]byte, 0, len(raw)+DeSmuMEFooterLength)
	out = append(out, raw...)
	out = append(out, DeSmuMEFooterText...)
	for _, v := range []uint32{
		n,                  // size: data actually written
		n,                  // padSize: data stored in the file
		deSmuMEType(n),     // type: index in save_types, 0 when unknown
		deSmuMEAddrSize(n), // addr_size
		n,                  // mem_size
		0,                  // version
	} {
		out = binary.LittleEndian.AppendUint32(out, v)
	}
	return append(out, DeSmuMECookie...), nil
}

// FlashcardSize is the minimum save file size of the flashcard profile.
// Flashcards such as the DSTT or the R4 commonly use 512 KiB files; the
// profile is marked "to_verify" until checked model by model.
const FlashcardSize = 512 << 10

// Flashcard handles flashcard .sav files: raw data padded with 0xFF to at
// least Size bytes. It never cuts: a larger save keeps its real size. On
// import the file is kept as is; the server's size rules cut the padding down
// to the game's chip size.
type Flashcard struct{ Size int }

func (Flashcard) ID() string        { return "flashcard" }
func (Flashcard) Extension() string { return ".sav" }

// Encode pads raw with 0xFF up to max(Size, len(raw)).
func (f Flashcard) Encode(raw []byte) ([]byte, error) {
	return f.EncodeForChip(raw, 0)
}

// EncodeForChip pads raw with 0xFF up to max(Size, chipSize, len(raw)), so
// that the file has the size the flashcard expects and nothing is cut.
func (f Flashcard) EncodeForChip(raw []byte, chipSize int64) ([]byte, error) {
	size := max(f.Size, len(raw))
	if chipSize > int64(size) {
		size = int(chipSize)
	}
	out := make([]byte, size)
	copy(out, raw)
	for i := len(raw); i < size; i++ {
		out[i] = 0xFF
	}
	return out, nil
}

func (Flashcard) Decode(file []byte) ([]byte, error) { return bytes.Clone(file), nil }

// ErrNotDeSmuME is returned when a file does not end with a DeSmuME footer.
var ErrNotDeSmuME = errors.New("convert: not a DeSmuME save (footer not found)")

// IsDeSmuME reports whether file ends with a DeSmuME footer.
func IsDeSmuME(file []byte) bool {
	return len(file) >= DeSmuMEFooterLength && bytes.HasSuffix(file, []byte(DeSmuMECookie))
}

// Decode validates the footer the way DeSmuME does (cookie, version 0,
// padSize equal to the data length) and returns the padSize data bytes.
// The type field is ignored: DeSmuME itself may leave it at 0.
func (DeSmuME) Decode(file []byte) ([]byte, error) {
	if !IsDeSmuME(file) {
		return nil, ErrNotDeSmuME
	}
	footer := file[len(file)-DeSmuMEFooterLength:]
	fields := footer[len(DeSmuMEFooterText) : len(DeSmuMEFooterText)+24]
	padSize := binary.LittleEndian.Uint32(fields[4:8])
	version := binary.LittleEndian.Uint32(fields[20:24])
	if version != 0 {
		return nil, fmt.Errorf("convert: unsupported DeSmuME footer version %d", version)
	}
	dataLen := len(file) - DeSmuMEFooterLength
	if int(padSize) != dataLen {
		return nil, fmt.Errorf("convert: DeSmuME footer announces %d bytes, file holds %d", padSize, dataLen)
	}
	return bytes.Clone(file[:dataLen]), nil
}
