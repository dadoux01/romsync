// Package systems describes the consoles whose saves RomSync syncs (see
// docs/SPEC.md, "Multi-consoles"): how their game identifiers look and which
// save sizes their cartridges have.
package systems

import (
	"regexp"
	"strings"
)

// System is a console.
type System struct {
	// ID is stored in games.system and returned by the API ("nds", "gba").
	ID string
	// Prefix starts the game identifiers of this console ("gba:"); the
	// Nintendo DS has none, for the identifiers stored before phase 7.
	Prefix string
	// ChipSizes are the valid save chip sizes, smallest first.
	ChipSizes []int64
}

// Identifier forms after the prefix (docs/SPEC.md, "Identification des jeux").
var (
	cartridgeRE = regexp.MustCompile(`^[A-Z0-9]{4}$`)
	romHashRE   = regexp.MustCompile(`^h:[0-9a-f]{40}$`)
	customRE    = regexp.MustCompile(`^x:[a-z0-9-]{1,32}$`)
)

var (
	// NDS is the Nintendo DS (and DSi): the sizes known to DeSmuME and
	// melonDS (EEPROM, FRAM, flash and NAND).
	NDS = &System{ID: "nds", ChipSizes: []int64{
		512, 8 << 10, 32 << 10, 64 << 10, 128 << 10, 256 << 10, 512 << 10,
		1 << 20, 2 << 20, 4 << 20, 8 << 20, 16 << 20, 32 << 20, 64 << 20,
	}}
	// GBA is the Game Boy Advance: EEPROM 4 and 64 Kbit, SRAM, flash 512
	// Kbit (or SRAM 64 KiB) and flash 1 Mbit, as in mGBA's memory.h.
	GBA = &System{ID: "gba", Prefix: "gba:", ChipSizes: []int64{512, 8 << 10, 32 << 10, 64 << 10, 128 << 10}}

	// All lists the consoles, the Nintendo DS first.
	All = []*System{NDS, GBA}
)

// ByID returns the console with the given ID.
func ByID(id string) (*System, bool) {
	for _, s := range All {
		if s.ID == id {
			return s, true
		}
	}
	return nil, false
}

// Parse returns the console of a game identifier and the identifier without
// its prefix; ok is false when the identifier is not valid for its console.
func Parse(code string) (s *System, local string, ok bool) {
	s, local = NDS, code
	for _, sys := range All {
		if sys.Prefix != "" && strings.HasPrefix(code, sys.Prefix) {
			s, local = sys, code[len(sys.Prefix):]
			break
		}
	}
	ok = cartridgeRE.MatchString(local) || romHashRE.MatchString(local) || customRE.MatchString(local)
	return s, local, ok
}

// Region returns the region letter of a cartridge code (the 4th character,
// as on the DS and the GBA), or nil.
func Region(code string) *string {
	_, local, ok := Parse(code)
	if !ok || !cartridgeRE.MatchString(local) {
		return nil
	}
	r := local[3:]
	return &r
}

// IsValidChipSize reports whether n is the size of a save chip of s.
func (s *System) IsValidChipSize(n int64) bool {
	for _, c := range s.ChipSizes {
		if c == n {
			return true
		}
	}
	return false
}
