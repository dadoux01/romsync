package chipdb

import "testing"

func TestKnownGames(t *testing.T) {
	if Len() < 6000 {
		t.Fatalf("only %d games loaded", Len())
	}
	for code, want := range map[string]int64{
		"IRBF": 512 << 10, // Pokémon Version Noire (FR)
		"CPUF": 512 << 10, // Pokémon Platine (FR), checked against real .dsv files
		"YKWE": 64 << 10,
	} {
		if got, ok := Size(code); !ok || got != want {
			t.Errorf("%s: got %d %v, want %d", code, got, ok, want)
		}
	}
	for _, code := range []string{"ZZZZ", "x:hack", "h:0123", ""} {
		if _, ok := Size(code); ok {
			t.Errorf("%q must be unknown", code)
		}
	}
}
