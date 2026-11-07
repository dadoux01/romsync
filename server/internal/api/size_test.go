package api

import (
	"bytes"
	"fmt"
	"testing"
	"time"
)

const (
	k64  = 64 << 10
	k512 = 512 << 10
)

// gameData returns n bytes of real (non-padding) save data.
func gameData(n int, seed byte) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(i*7) + seed
	}
	return b
}

func fill(data []byte, total int, b byte) []byte {
	return append(bytes.Clone(data), bytes.Repeat([]byte{b}, total-len(data))...)
}

func (c *client) chipSize(code string) int64 {
	c.env.t.Helper()
	var games struct{ Games []gameJSON }
	c.get("/api/v1/games").json(c.env.t, &games)
	for _, g := range games.Games {
		if g.Code == code && g.ChipSize != nil {
			return *g.ChipSize
		}
	}
	c.env.t.Fatalf("no chip size for %s", code)
	return 0
}

func TestHalfBlankSaveIsNeverCutWithoutSmallerUpload(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	// x: identifiers are never in the size database.
	v1 := dev.uploadOK(upload{code: "x:half", data: fill(gameData(k512/2, 1), k512, 0xFF), savedAt: t0}, 201).Version
	v2 := dev.uploadOK(upload{code: "x:half", data: fill(gameData(k512/2, 2), k512, 0xFF), savedAt: t0.Add(time.Minute), base: v1.ID}, 201).Version
	if v1.Size != k512 || v2.Size != k512 || v1.SizeEvent != nil || v2.SizeEvent != nil || dev.chipSize("x:half") != k512 {
		t.Fatalf("a half-blank save must be kept whole: %+v %+v", v1, v2)
	}
}

func TestFlashcardThenEmulatorConvergesToRealSize(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)
	save := gameData(k64, 3)

	// DSTT: the save is padded to 512 KiB by the flashcard.
	v1 := admin.uploadOK(upload{code: "x:dstt", data: fill(save, k512, 0xFF), savedAt: t0}, 201).Version
	if v1.Size != k512 {
		t.Fatalf("unexpected first size %d", v1.Size)
	}
	// melonDS: the real 64 KiB save.
	v2 := dev.uploadOK(upload{code: "x:dstt", data: gameData(k64, 4), savedAt: t0.Add(time.Minute), base: v1.ID}, 201).Version
	if v2.Size != k64 || v2.SizeEvent == nil || *v2.SizeEvent != (sizeEventJSON{Type: "shrunk", From: k512}) || dev.chipSize("x:dstt") != k64 {
		t.Fatalf("chip size must shrink to 64 KiB: %+v", v2)
	}
	// DSTT again: trimmed to 64 KiB.
	r3 := admin.uploadOK(upload{code: "x:dstt", data: fill(gameData(k64, 5), k512, 0xFF), savedAt: t0.Add(2 * time.Minute), base: v2.ID}, 201)
	if r3.Version.Size != k64 || *r3.Version.SizeEvent != (sizeEventJSON{Type: "trimmed", From: k512}) {
		t.Fatalf("flashcard upload must be trimmed: %+v", r3.Version)
	}
	r := dev.get(fmt.Sprintf("/api/v1/versions/%d/content", r3.Version.ID))
	if !bytes.Equal(r.body, gameData(k64, 5)) {
		t.Fatal("trimmed content differs")
	}

	// Export to a flashcard pads back to 512 KiB with 0xFF.
	r = admin.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=flashcard", r3.Version.ID))
	expect(t, r, 200)
	if !bytes.Equal(r.body, fill(gameData(k64, 5), k512, 0xFF)) {
		t.Fatalf("flashcard export must be padded to 512 KiB, got %d bytes", len(r.body))
	}
}

func TestNonPaddingExcessIsASizeMismatch(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	v1 := dev.uploadOK(upload{code: "x:full", data: gameData(k512, 1), savedAt: t0}, 201).Version
	// Smaller, but the active version has data beyond 64 KiB.
	expectErr(t, dev.upload(upload{code: "x:full", data: gameData(k64, 2), savedAt: t0.Add(time.Minute), base: v1.ID}), 409, "size_mismatch")

	dev.uploadOK(upload{code: "x:small", data: gameData(k64, 1), savedAt: t0}, 201)
	// Larger, with data beyond 64 KiB.
	expectErr(t, dev.upload(upload{code: "x:small", data: gameData(k512, 2), savedAt: t0.Add(time.Minute)}), 409, "size_mismatch")
	// Mixed 0x00/0xFF excess is not padding.
	mixed := append(gameData(k64, 3), fill([]byte{0x00}, k512-k64, 0xFF)...)
	expectErr(t, dev.upload(upload{code: "x:small", data: mixed, savedAt: t0.Add(time.Minute)}), 409, "size_mismatch")

	// Forcing from the web interface is traced.
	r := admin.uploadOK(upload{code: "x:small", data: gameData(k512, 2), savedAt: t0.Add(time.Minute),
		headers: map[string]string{"X-Force-Size": "true"}}, 201)
	if *r.Version.SizeEvent != (sizeEventJSON{Type: "forced", From: k64}) || admin.chipSize("x:small") != k512 {
		t.Fatalf("forced upload: %+v", r.Version)
	}
}

func TestSizeDatabaseSetsChipSize(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	// YKWE is a 64 KiB game in the database: a flashcard file padded to
	// 512 KiB is trimmed from the very first upload.
	v := dev.uploadOK(upload{code: "YKWE", data: fill(gameData(k64, 1), k512, 0xFF), savedAt: t0}, 201).Version
	if v.Size != k64 || *v.SizeEvent != (sizeEventJSON{Type: "trimmed", From: k512}) || dev.chipSize("YKWE") != k64 {
		t.Fatalf("database size must apply: %+v", v)
	}
	// A real 512 KiB save of a 512 KiB game is kept whole.
	v = dev.uploadOK(upload{code: "CPUF", data: fill(gameData(k512/2, 1), k512, 0xFF), savedAt: t0}, 201).Version
	if v.Size != k512 || v.SizeEvent != nil {
		t.Fatalf("unexpected %+v", v)
	}
}
