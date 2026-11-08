package api

import (
	"bytes"
	"fmt"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/dadoux01/romsync/server/internal/blobs"
)

// upload describes a save upload.
type upload struct {
	code     string
	data     []byte
	savedAt  time.Time
	base     int64 // 0 = empty header
	uploadID string
	headers  map[string]string
	query    string
}

var uploadSeq int

func (c *client) upload(u upload) response {
	c.env.t.Helper()
	if u.uploadID == "" {
		uploadSeq++
		u.uploadID = fmt.Sprintf("upload-%d", uploadSeq)
	}
	h := map[string]string{
		"Content-Type":     "application/octet-stream",
		"X-Upload-Id":      u.uploadID,
		"X-Saved-At":       u.savedAt.Format(time.RFC3339Nano),
		"X-Emulator":       "melonds",
		"X-Content-SHA256": blobs.Sum(u.data),
	}
	if u.base != 0 {
		h["X-Base-Version"] = strconv.FormatInt(u.base, 10)
	}
	for k, v := range u.headers {
		h[k] = v
	}
	return c.do(http.MethodPost, "/api/v1/games/"+u.code+"/versions"+u.query, bytes.NewReader(u.data), h)
}

func (c *client) uploadOK(u upload, wantStatus int) uploadResult {
	c.env.t.Helper()
	r := c.upload(u)
	expect(c.env.t, r, wantStatus)
	var res uploadResult
	r.json(c.env.t, &res)
	return res
}

// save returns a 512-byte save filled with b.
func save(b byte) []byte { return bytes.Repeat([]byte{b}, 512) }

func (c *client) active(code string) versionJSON {
	c.env.t.Helper()
	var res struct{ Version versionJSON }
	r := c.get("/api/v1/games/" + code + "/active")
	expect(c.env.t, r, 200)
	r.json(c.env.t, &res)
	return res.Version
}

func TestUploadFirstSaveCreatesGame(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, devInfo := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	res := dev.uploadOK(upload{code: "IRBF", data: save(1), savedAt: t0,
		headers: map[string]string{"X-Game-Title": "Pok%C3%A9mon Noire"}}, 201)
	if !res.Created || !res.Active || res.Conflict {
		t.Fatalf("unexpected result %+v", res)
	}
	v := res.Version
	if v.Size != 512 || v.SHA256 != blobs.Sum(save(1)) || v.DeviceID == nil || *v.DeviceID != devInfo.ID ||
		v.Emulator != "melonds" || v.SavedAt != "2026-11-07T11:00:00.000Z" || v.UploadedAt != "2026-11-07T12:00:00.000Z" {
		t.Fatalf("unexpected version %+v", v)
	}

	var games struct{ Games []gameJSON }
	dev.get("/api/v1/games").json(t, &games)
	if len(games.Games) != 1 {
		t.Fatalf("expected 1 game, got %d", len(games.Games))
	}
	g := games.Games[0]
	if g.Code != "IRBF" || g.Title != "Pokémon Noire" || g.Region == nil || *g.Region != "F" ||
		g.ChipSize == nil || *g.ChipSize != 512 || g.ActiveVersion == nil || g.ActiveVersion.ID != v.ID || g.VersionCount != 1 {
		t.Fatalf("unexpected game %+v", g)
	}
	if got := dev.active("IRBF"); got.ID != v.ID {
		t.Fatalf("active is %d, want %d", got.ID, v.ID)
	}
}

func TestMostRecentWins(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	pc, _ := e.pairDevice(admin, "PC")
	phone, _ := e.pairDevice(admin, "Phone")
	t0 := e.clock.Now().Add(-2 * time.Hour)

	v1 := pc.uploadOK(upload{code: "IRBF", data: save(1), savedAt: t0}, 201).Version

	// Normal progression on top of the active version.
	r2 := pc.uploadOK(upload{code: "IRBF", data: save(2), savedAt: t0.Add(10 * time.Minute), base: v1.ID}, 201)
	if !r2.Active || r2.Conflict {
		t.Fatalf("v2: %+v", r2)
	}

	// The phone played offline from v1, later than v2: it wins, with a conflict.
	r3 := phone.uploadOK(upload{code: "IRBF", data: save(3), savedAt: t0.Add(20 * time.Minute), base: v1.ID}, 201)
	if !r3.Active || !r3.Conflict {
		t.Fatalf("v3: %+v", r3)
	}

	// An older divergent save is kept in history but does not become active.
	r4 := pc.uploadOK(upload{code: "IRBF", data: save(4), savedAt: t0.Add(15 * time.Minute), base: r2.Version.ID}, 201)
	if r4.Active || !r4.Conflict {
		t.Fatalf("v4: %+v", r4)
	}
	if got := pc.active("IRBF"); got.ID != r3.Version.ID {
		t.Fatalf("active is %d, want v3 %d", got.ID, r3.Version.ID)
	}

	// Equal saved_at keeps the active version.
	r5 := pc.uploadOK(upload{code: "IRBF", data: save(5), savedAt: t0.Add(20 * time.Minute), base: r3.Version.ID}, 201)
	if r5.Active || r5.Conflict {
		t.Fatalf("v5: %+v", r5)
	}

	var games struct{ Games []gameJSON }
	pc.get("/api/v1/games").json(t, &games)
	if games.Games[0].VersionCount != 5 || games.Games[0].Conflict {
		t.Fatalf("unexpected game summary %+v", games.Games[0])
	}
}

func TestUploadIdempotence(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	u := upload{code: "IRBF", data: save(1), savedAt: t0, uploadID: "3f2a-retry"}
	first := dev.uploadOK(u, 201)
	again := dev.uploadOK(u, 201)
	if again.Version.ID != first.Version.ID || !again.Created || !again.Active {
		t.Fatalf("retry must return the original response: %+v vs %+v", again, first)
	}

	// Same content as the active version under a new upload id: ignored.
	same := dev.uploadOK(upload{code: "IRBF", data: save(1), savedAt: t0.Add(time.Minute), base: first.Version.ID}, 200)
	if same.Created || same.Version.ID != first.Version.ID {
		t.Fatalf("identical save must be ignored: %+v", same)
	}

	// Reusing an upload id for another game is refused.
	expectErr(t, dev.upload(upload{code: "IRBE", data: save(2), savedAt: t0, uploadID: "3f2a-retry"}), 409, "conflict")

	var page struct{ Versions []versionJSON }
	dev.get("/api/v1/games/IRBF/versions").json(t, &page)
	if len(page.Versions) != 1 {
		t.Fatalf("expected exactly 1 version, got %d", len(page.Versions))
	}

	// Upload ids are scoped per account.
	alice := e.newUser(admin, "alice")
	aliceDev, _ := e.pairDevice(alice, "Alice PC")
	r := aliceDev.uploadOK(upload{code: "IRBF", data: save(9), savedAt: t0, uploadID: "3f2a-retry"}, 201)
	if r.Version.ID == first.Version.ID {
		t.Fatal("another account must get its own version")
	}
}

func TestFutureSavedAtIsClampedAndDeviceFlagged(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	bad, badInfo := e.pairDevice(admin, "Wrong clock")
	good, _ := e.pairDevice(admin, "PC")
	now := e.clock.Now()

	future := now.AddDate(1, 0, 0)
	r := bad.uploadOK(upload{code: "IRBF", data: save(1), savedAt: future}, 201)
	v := r.Version
	if v.SavedAt != "2026-11-07T12:00:00.000Z" {
		t.Fatalf("saved_at must be clamped to the reception time, got %s", v.SavedAt)
	}
	if v.SavedAtReported == nil || *v.SavedAtReported != "2027-11-07T12:00:00.000Z" {
		t.Fatalf("reported saved_at must be kept, got %v", v.SavedAtReported)
	}
	var devs struct{ Devices []deviceJSON }
	admin.get("/api/v1/devices").json(t, &devs)
	for _, d := range devs.Devices {
		if (d.ID == badInfo.ID) != (d.ClockSkewAt != nil) {
			t.Fatalf("only the wrong-clock device must be flagged: %+v", d)
		}
	}

	// Without the clamp this save from a correct clock would never win.
	e.clock.Advance(time.Hour)
	r2 := good.uploadOK(upload{code: "IRBF", data: save(2), savedAt: e.clock.Now(), base: v.ID}, 201)
	if !r2.Active {
		t.Fatal("a later save must replace the clamped one")
	}

	// Within the 5-minute tolerance nothing is changed.
	r3 := good.uploadOK(upload{code: "IRBF", data: save(3), savedAt: e.clock.Now().Add(4 * time.Minute), base: r2.Version.ID}, 201)
	if r3.Version.SavedAtReported != nil || r3.Version.SavedAt != "2026-11-07T13:04:00.000Z" {
		t.Fatalf("tolerated skew must not be corrected: %+v", r3.Version)
	}
}

func TestUploadValidation(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now()

	expectErr(t, dev.upload(upload{code: "irbf", data: save(1), savedAt: t0}), 400, "invalid_request")
	expectErr(t, dev.upload(upload{code: "IRBF", data: save(1), savedAt: t0, uploadID: "bad id!"}), 400, "invalid_request")
	expectErr(t, dev.upload(upload{code: "IRBF", data: save(1), savedAt: t0,
		headers: map[string]string{"X-Saved-At": "yesterday"}}), 400, "invalid_request")
	expectErr(t, dev.upload(upload{code: "IRBF", data: save(1), savedAt: t0,
		headers: map[string]string{"X-Content-SHA256": blobs.Sum(save(2))}}), 400, "hash_mismatch")
	expectErr(t, dev.upload(upload{code: "IRBF", data: []byte{}, savedAt: t0}), 400, "invalid_request")
	expectErr(t, dev.upload(upload{code: "IRBF", data: make([]byte, e.cfg.MaxUpload+1), savedAt: t0}), 413, "too_large")
	expectErr(t, e.client().upload(upload{code: "IRBF", data: save(1), savedAt: t0}), 401, "unauthorized")

	// Other identifier formats, including an encoded colon.
	h := "h:0123456789abcdef0123456789abcdef01234567"
	dev.uploadOK(upload{code: h, data: save(1), savedAt: t0}, 201)
	dev.uploadOK(upload{code: "h%3A0123456789abcdef0123456789abcdef01234567", data: save(2), savedAt: t0.Add(time.Second)}, 201)
	if got := dev.active(h); got.GameCode != h {
		t.Fatalf("unexpected game code %q", got.GameCode)
	}
	dev.uploadOK(upload{code: "x:my-hack", data: save(1), savedAt: t0}, 201)
	expectErr(t, dev.upload(upload{code: "x:My_Hack", data: save(1), savedAt: t0}), 400, "invalid_request")
}

func TestChipSize(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	v1 := dev.uploadOK(upload{code: "IRBF", data: save(1), savedAt: t0}, 201).Version
	big := bytes.Repeat([]byte{7}, 8192)
	expectErr(t, dev.upload(upload{code: "IRBF", data: big, savedAt: t0.Add(time.Minute), base: v1.ID}), 409, "size_mismatch")
	expectErr(t, dev.upload(upload{code: "IRBF", data: big, savedAt: t0.Add(time.Minute), base: v1.ID,
		headers: map[string]string{"X-Force-Size": "true"}}), 403, "forbidden")

	// The web interface may force it, which updates the known size.
	admin.uploadOK(upload{code: "IRBF", data: big, savedAt: t0.Add(time.Minute), base: v1.ID,
		headers: map[string]string{"X-Force-Size": "true"}}, 201)
	var games struct{ Games []gameJSON }
	admin.get("/api/v1/games").json(t, &games)
	if *games.Games[0].ChipSize != 8192 {
		t.Fatalf("chip size not updated: %d", *games.Games[0].ChipSize)
	}
	expectErr(t, dev.upload(upload{code: "IRBF", data: save(3), savedAt: t0.Add(2 * time.Minute)}), 409, "size_mismatch")
}

func TestContentActivatePinAndPagination(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-24 * time.Hour)

	var ids []int64
	var base int64
	for i := 0; i < 5; i++ {
		v := dev.uploadOK(upload{code: "IRBF", data: save(byte(i + 1)), savedAt: t0.Add(time.Duration(i) * time.Hour), base: base}, 201).Version
		ids = append(ids, v.ID)
		base = v.ID
	}

	// Download.
	r := dev.get(fmt.Sprintf("/api/v1/versions/%d/content", ids[1]))
	expect(t, r, 200)
	if !bytes.Equal(r.body, save(2)) || r.header.Get("X-Content-SHA256") != blobs.Sum(save(2)) {
		t.Fatal("unexpected content")
	}

	// Pagination, newest first.
	var page struct {
		Versions   []versionJSON
		NextBefore *int64 `json:"next_before"`
	}
	dev.get("/api/v1/games/IRBF/versions?limit=2").json(t, &page)
	if len(page.Versions) != 2 || page.Versions[0].ID != ids[4] || page.Versions[1].ID != ids[3] || page.NextBefore == nil {
		t.Fatalf("unexpected first page %+v", page)
	}
	dev.get(fmt.Sprintf("/api/v1/games/IRBF/versions?limit=2&before=%d", *page.NextBefore)).json(t, &page)
	if len(page.Versions) != 2 || page.Versions[0].ID != ids[2] || page.Versions[1].ID != ids[1] {
		t.Fatalf("unexpected second page %+v", page)
	}
	dev.get(fmt.Sprintf("/api/v1/games/IRBF/versions?limit=2&before=%d", *page.NextBefore)).json(t, &page)
	if len(page.Versions) != 1 || page.NextBefore != nil {
		t.Fatalf("unexpected last page %+v", page)
	}
	expectErr(t, dev.get("/api/v1/games/IRBF/versions?limit=500"), 400, "invalid_request")

	// Restore an old version (web session only).
	expectErr(t, dev.post(fmt.Sprintf("/api/v1/versions/%d/activate", ids[1]), nil), 403, "forbidden")
	expect(t, admin.post(fmt.Sprintf("/api/v1/versions/%d/activate", ids[1]), nil), 200)
	if got := dev.active("IRBF"); got.ID != ids[1] {
		t.Fatalf("active is %d, want %d", got.ID, ids[1])
	}

	// Pin and annotate.
	var pv struct{ Version versionJSON }
	r = admin.patch(fmt.Sprintf("/api/v1/versions/%d", ids[0]), map[string]any{"pinned": true, "note": " avant la Ligue "})
	expect(t, r, 200)
	r.json(t, &pv)
	if !pv.Version.Pinned || pv.Version.Note != "avant la Ligue" {
		t.Fatalf("unexpected version %+v", pv.Version)
	}

	// Rename and per-game retention.
	var pg struct{ Game gameJSON }
	r = admin.patch("/api/v1/games/IRBF", map[string]any{"title": "Pokémon Noire", "retention_policy": map[string]any{"mode": "last_n", "n": 3}})
	expect(t, r, 200)
	r.json(t, &pg)
	if pg.Game.Title != "Pokémon Noire" || pg.Game.RetentionPolicy == nil || pg.Game.RetentionPolicy.N != 3 {
		t.Fatalf("unexpected game %+v", pg.Game)
	}
	r = admin.patch("/api/v1/games/IRBF", map[string]any{"retention_policy": nil})
	expect(t, r, 200)
	r.json(t, &pg)
	if pg.Game.RetentionPolicy != nil || pg.Game.Title != "Pokémon Noire" {
		t.Fatalf("null must restore inheritance: %+v", pg.Game)
	}
	expectErr(t, admin.patch("/api/v1/games/IRBF", map[string]any{"title": ""}), 400, "invalid_request")
	expectErr(t, admin.patch("/api/v1/games/ZZZZ", map[string]any{"title": "x"}), 404, "not_found")
}

func TestSavesAreScopedToTheirAccount(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	v := dev.uploadOK(upload{code: "IRBF", data: save(1), savedAt: e.clock.Now()}, 201).Version

	alice := e.newUser(admin, "alice")
	expectErr(t, alice.get("/api/v1/games/IRBF/active"), 404, "not_found")
	expectErr(t, alice.get("/api/v1/games/IRBF/versions"), 404, "not_found")
	expectErr(t, alice.get(fmt.Sprintf("/api/v1/versions/%d/content", v.ID)), 404, "not_found")
	expectErr(t, alice.post(fmt.Sprintf("/api/v1/versions/%d/activate", v.ID), nil), 404, "not_found")
	expectErr(t, alice.patch(fmt.Sprintf("/api/v1/versions/%d", v.ID), map[string]bool{"pinned": true}), 404, "not_found")
	var games struct{ Games []gameJSON }
	alice.get("/api/v1/games").json(t, &games)
	if len(games.Games) != 0 {
		t.Fatal("alice must not see admin's games")
	}
}

func TestDeduplicatedBlobs(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)
	// The same content in two games is stored once.
	a := dev.uploadOK(upload{code: "IRBF", data: save(1), savedAt: t0}, 201).Version
	b := dev.uploadOK(upload{code: "IRBE", data: save(1), savedAt: t0}, 201).Version
	if a.SHA256 != b.SHA256 {
		t.Fatal("hashes must match")
	}
	var n int
	if err := e.srv.db.QueryRow(`SELECT COUNT(DISTINCT blob_hash) FROM save_versions`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("expected 1 distinct blob, got %d (%v)", n, err)
	}
}

func TestDeleteVersion(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "PC")
	t0 := e.clock.Now().Add(-time.Hour)

	var ids []int64
	var base int64
	for i := 0; i < 3; i++ {
		v := dev.uploadOK(upload{code: "IRBF", data: save(byte(i + 1)), savedAt: t0.Add(time.Duration(i) * time.Minute), base: base}, 201).Version
		ids = append(ids, v.ID)
		base = v.ID
	}
	path := func(id int64) string { return fmt.Sprintf("/api/v1/versions/%d", id) }

	// Web session only; the active and pinned versions are protected.
	expectErr(t, dev.delete(path(ids[0])), 403, "forbidden")
	expectErr(t, admin.delete(path(ids[2])), 409, "conflict")
	expect(t, admin.patch(path(ids[0]), map[string]any{"pinned": true}), 200)
	expectErr(t, admin.delete(path(ids[0])), 409, "conflict")

	// An old version: gone from the history, the others are untouched (the
	// next one still names it as its base).
	expect(t, admin.delete(path(ids[1])), 204)
	expectErr(t, admin.delete(path(ids[1])), 404, "not_found")
	var page struct{ Versions []versionJSON }
	admin.get("/api/v1/games/IRBF/versions").json(t, &page)
	if len(page.Versions) != 2 || page.Versions[0].ID != ids[2] || page.Versions[1].ID != ids[0] {
		t.Fatalf("unexpected history %+v", page.Versions)
	}
	if b := page.Versions[0].BaseVersionID; b == nil || *b != ids[1] {
		t.Fatalf("base of the next version changed: %v", b)
	}
	if got := dev.active("IRBF"); got.ID != ids[2] {
		t.Fatalf("active is %d, want %d", got.ID, ids[2])
	}

	// Another account cannot delete it.
	other := e.newUser(admin, "bob")
	expectErr(t, other.delete(path(ids[0])), 404, "not_found")
}
