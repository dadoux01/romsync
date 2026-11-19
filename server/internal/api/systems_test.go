package api

import (
	"bytes"
	"fmt"
	"testing"
	"time"
)

// docs/SPEC.md, "Multi-consoles": GBA games next to DS games.
func TestGBAGamesNextToDSGames(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	// The same 4 characters on two consoles are two games.
	dev.uploadOK(upload{code: "BPEF", data: save(1), savedAt: t0}, 201)
	gba := dev.uploadOK(upload{code: "gba:BPEF", data: gameData(32<<10, 2), savedAt: t0}, 201).Version
	if gba.GameCode != "gba:BPEF" || dev.chipSize("gba:BPEF") != 32<<10 || dev.chipSize("BPEF") != 512 {
		t.Fatalf("unexpected games: %+v", gba)
	}

	var all struct{ Games []gameJSON }
	dev.get("/api/v1/games").json(t, &all)
	systems := map[string]string{}
	for _, g := range all.Games {
		systems[g.Code] = g.System
		if g.Region == nil || *g.Region != "F" {
			t.Errorf("%s: region %v", g.Code, g.Region)
		}
	}
	if systems["BPEF"] != "nds" || systems["gba:BPEF"] != "gba" {
		t.Fatalf("systems: %v", systems)
	}
	var onlyGBA struct{ Games []gameJSON }
	dev.get("/api/v1/games?system=gba").json(t, &onlyGBA)
	if len(onlyGBA.Games) != 1 || onlyGBA.Games[0].Code != "gba:BPEF" {
		t.Fatalf("filter: %+v", onlyGBA.Games)
	}
	expectErr(t, dev.get("/api/v1/games?system=psx"), 400, "invalid_request")
}

func TestGBAIdentifiersAndSizes(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	for _, bad := range []string{"gba:bpef", "gba:", "psx:ABCD", "gba:gba:BPEF"} {
		expectErr(t, dev.upload(upload{code: bad, data: save(1), savedAt: t0}), 400, "invalid_request")
	}
	// A RetroArch .srm before the game's first save: 128 KiB of 0xFF, then
	// the real 32 KiB SRAM shrinks the chip size.
	blank := bytes.Repeat([]byte{0xFF}, 128<<10)
	v1 := dev.uploadOK(upload{code: "gba:x:srm", data: blank, savedAt: t0}, 201).Version
	v2 := dev.uploadOK(upload{code: "gba:x:srm", data: gameData(32<<10, 3), savedAt: t0.Add(time.Minute), base: v1.ID}, 201).Version
	if v2.SizeEvent == nil || v2.SizeEvent.Type != "shrunk" || dev.chipSize("gba:x:srm") != 32<<10 {
		t.Fatalf("the chip size must shrink to 32 KiB: %+v", v2)
	}
	// A larger save holding data beyond the chip size is refused.
	expectErr(t, dev.upload(upload{code: "gba:x:srm", data: gameData(64<<10, 4), savedAt: t0.Add(2 * time.Minute), base: v2.ID}),
		409, "size_mismatch")
}

func TestMGBAProfileRemovesTheClock(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	t0 := e.clock.Now().Add(-time.Hour)

	sram := gameData(32<<10, 5)
	withClock := append(bytes.Clone(sram), gameData(16, 9)...)
	v := admin.uploadOK(upload{code: "gba:BPEE", data: withClock, savedAt: t0, query: "?profile=mgba"}, 201).Version
	if v.Size != 32<<10 {
		t.Fatalf("the clock must be removed: %d bytes", v.Size)
	}
	r := admin.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=mgba", v.ID))
	expect(t, r, 200)
	if !bytes.Equal(r.body, sram) {
		t.Fatal("export must be the raw save")
	}
	// DS profiles do not convert GBA saves, and the reverse.
	expectErr(t, admin.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=desmume", v.ID)), 400, "invalid_request")
	expectErr(t, admin.upload(upload{code: "IRBF", data: save(1), savedAt: t0, query: "?profile=mgba"}), 400, "invalid_request")
}
