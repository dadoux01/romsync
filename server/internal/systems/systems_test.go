package systems

import "testing"

func TestParse(t *testing.T) {
	cases := []struct {
		code, system, local string
		ok                  bool
	}{
		// The DS identifiers of phase 1 to 6 are unchanged.
		{"IRBF", "nds", "IRBF", true},
		{"h:" + "a1b2c3d4e5a1b2c3d4e5a1b2c3d4e5a1b2c3d4e5", "nds", "h:a1b2c3d4e5a1b2c3d4e5a1b2c3d4e5a1b2c3d4e5", true},
		{"x:my-hack", "nds", "x:my-hack", true},
		{"gba:BPEF", "gba", "BPEF", true},
		{"gba:x:emerald-hack", "gba", "x:emerald-hack", true},
		{"gba:h:" + "0123456789012345678901234567890123456789", "gba", "h:0123456789012345678901234567890123456789", true},
		{"irbf", "nds", "irbf", false},
		{"gba:", "gba", "", false},
		{"gba:bpef", "gba", "bpef", false},
		{"snes:ABCD", "nds", "snes:ABCD", false}, // not a console yet
		{"gba:gba:BPEF", "gba", "gba:BPEF", false},
		{"gb:h:" + "0123456789012345678901234567890123456789", "gb", "h:0123456789012345678901234567890123456789", true},
		{"gb:x:red-fr", "gb", "x:red-fr", true},
		{"gb:APSE", "gb", "APSE", false}, // no cartridge code on the Game Boy
		{"3ds:0004000000055D00", "3ds", "0004000000055D00", true},
		{"3ds:0004000000055d00", "3ds", "0004000000055d00", false},
		{"3ds:x:pokemon-y", "3ds", "x:pokemon-y", true},
		{"3ds:h:" + "0123456789012345678901234567890123456789", "3ds", "h:0123456789012345678901234567890123456789", false},
	}
	for _, c := range cases {
		s, local, ok := Parse(c.code)
		if s.ID != c.system || local != c.local || ok != c.ok {
			t.Errorf("Parse(%q) = %s %q %v, want %s %q %v", c.code, s.ID, local, ok, c.system, c.local, c.ok)
		}
	}
}

func TestRegion(t *testing.T) {
	if r := Region("IRBF"); r == nil || *r != "F" {
		t.Errorf("Region(IRBF) = %v", r)
	}
	if r := Region("gba:BPEF"); r == nil || *r != "F" {
		t.Errorf("Region(gba:BPEF) = %v", r)
	}
	if Region("gba:x:hack") != nil || Region("x:hack") != nil {
		t.Error("custom identifiers have no region")
	}
}

func TestChipSizes(t *testing.T) {
	if !GBA.IsValidChipSize(128<<10) || GBA.IsValidChipSize(256<<10) {
		t.Error("GBA chips go up to 128 KiB")
	}
	if !NDS.IsValidChipSize(64<<20) || NDS.IsValidChipSize(100) {
		t.Error("DS chip sizes")
	}
	if s, ok := ByID("gba"); !ok || s != GBA {
		t.Error("ByID(gba)")
	}
}
