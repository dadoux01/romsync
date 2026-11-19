package api

import (
	"archive/tar"
	"bytes"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/tree"
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

func TestGameBoyGames(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	t0 := e.clock.Now().Add(-time.Hour)

	// No cartridge code on the Game Boy: only h: and x: identifiers.
	expectErr(t, admin.upload(upload{code: "gb:APSE", data: save(1), savedAt: t0}), 400, "invalid_request")
	ram := gameData(8<<10, 6)
	withClock := append(bytes.Clone(ram), gameData(48, 7)...)
	code := "gb:h:" + "0123456789abcdef0123456789abcdef01234567"
	v := admin.uploadOK(upload{code: code, data: withClock, savedAt: t0, query: "?profile=mgba-gb"}, 201).Version
	if v.Size != 8<<10 || admin.chipSize(code) != 8<<10 {
		t.Fatalf("the 48-byte clock must be removed: %+v", v)
	}
	var games struct{ Games []gameJSON }
	admin.get("/api/v1/games?system=gb").json(t, &games)
	if len(games.Games) != 1 || games.Games[0].System != "gb" || games.Games[0].Region != nil {
		t.Fatalf("games: %+v", games.Games)
	}
	// Gambatte keeps a 64 KiB RAM in 128 KiB: the padding is cut.
	big := admin.uploadOK(upload{code: "gb:x:big", data: gameData(64<<10, 8), savedAt: t0}, 201).Version
	r := admin.uploadOK(upload{code: "gb:x:big", data: fill(gameData(64<<10, 9), 128<<10, 0x00), savedAt: t0.Add(time.Minute), base: big.ID}, 201)
	if r.Version.Size != 64<<10 || r.Version.SizeEvent == nil || r.Version.SizeEvent.Type != "trimmed" {
		t.Fatalf("Gambatte's padding must be cut: %+v", r.Version)
	}
}

// docs/SPEC.md, "Saves en dossier": a 3DS save is a folder, stored as its
// canonical archive.
func TestFolderSaves(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	t0 := e.clock.Now().Add(-time.Hour)
	const code = "3ds:0004000000055D00"

	// A tar made by another tool (owners, dates, "./"), no folder entries.
	var buf bytes.Buffer
	w := tar.NewWriter(&buf)
	for _, f := range []struct{ name, data string }{{"./00000001/main", "progress"}, {"./00000001/extra", "x"}} {
		_ = w.WriteHeader(&tar.Header{Name: f.name, Mode: 0o600, Size: int64(len(f.data)), Uid: 1000, ModTime: t0, Typeflag: tar.TypeReg})
		_, _ = w.Write([]byte(f.data))
	}
	_ = w.Close()
	v := admin.uploadOK(upload{code: code, data: buf.Bytes(), savedAt: t0}, 201).Version
	want, _ := tree.Canonical([]tree.Entry{{Path: "00000001/main", Data: []byte("progress")}, {Path: "00000001/extra", Data: []byte("x")}})
	if v.SHA256 != blobs.Sum(want) || v.Size != int64(len(want)) {
		t.Fatalf("the archive must be stored in canonical form: %+v", v)
	}
	r := admin.get(fmt.Sprintf("/api/v1/versions/%d/content", v.ID))
	if !bytes.Equal(r.body, want) || !strings.Contains(r.header.Get("Content-Disposition"), ".tar") {
		t.Fatal("content must be the canonical .tar")
	}
	// The same content as a canonical archive: nothing new.
	admin.uploadOK(upload{code: code, data: want, savedAt: t0.Add(time.Minute), base: v.ID}, 200)

	var games struct{ Games []gameJSON }
	admin.get("/api/v1/games?system=3ds").json(t, &games)
	if len(games.Games) != 1 || games.Games[0].ChipSize != nil || games.Games[0].Region != nil {
		t.Fatalf("a folder has no chip size: %+v", games.Games)
	}
	expectErr(t, admin.upload(upload{code: code, data: []byte("not a tar"), savedAt: t0}), 400, "invalid_request")
	expectErr(t, admin.upload(upload{code: "3ds:x:other", data: want, savedAt: t0, query: "?profile=desmume"}), 400, "invalid_request")
	expectErr(t, admin.upload(upload{code: "3ds:0004000000055d00", data: want, savedAt: t0}), 400, "invalid_request")
}
