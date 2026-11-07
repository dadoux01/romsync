package api

import (
	"bytes"
	"fmt"
	"testing"
	"time"

	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/convert"
)

func TestImportDeSmuMEAndExport(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	raw := bytes.Repeat([]byte{0xA5}, 8<<10)
	dsv := convert.DeSmuME{}.Encode(raw)

	// Web import of a .dsv: the hash covers the uploaded file, the server
	// stores the raw content.
	res := admin.uploadOK(upload{code: "IRBF", data: dsv, savedAt: e.clock.Now().Add(-time.Hour), query: "?profile=desmume"}, 201)
	if res.Version.Size != int64(len(raw)) || res.Version.SHA256 != blobs.Sum(raw) {
		t.Fatalf("expected the raw content to be stored, got %+v", res.Version)
	}
	if res.Version.DeviceID != nil {
		t.Fatal("a web import has no device")
	}

	id := res.Version.ID
	r := admin.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=desmume", id))
	expect(t, r, 200)
	if !bytes.Equal(r.body, dsv) {
		t.Fatal("DeSmuME export differs from the imported file")
	}
	if cd := r.header.Get("Content-Disposition"); cd != `attachment; filename="IRBF.dsv"` {
		t.Fatalf("unexpected Content-Disposition %q", cd)
	}

	r = admin.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=raw", id))
	expect(t, r, 200)
	if !bytes.Equal(r.body, raw) || r.header.Get("Content-Disposition") != `attachment; filename="IRBF.sav"` {
		t.Fatal("unexpected raw export")
	}

	expectErr(t, admin.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=nope", id)), 400, "invalid_request")
	expectErr(t, admin.get("/api/v1/versions/999/export?profile=raw"), 404, "not_found")

	// Export is a web-session route.
	dev, _ := e.pairDevice(admin, "PC")
	expectErr(t, dev.get(fmt.Sprintf("/api/v1/versions/%d/export?profile=raw", id)), 403, "forbidden")

	// A raw file sent as DeSmuME is rejected.
	expectErr(t, admin.upload(upload{code: "IRBF", data: raw, savedAt: e.clock.Now(), query: "?profile=desmume"}), 400, "invalid_request")
	expectErr(t, admin.upload(upload{code: "IRBF", data: raw, savedAt: e.clock.Now(), query: "?profile=nope"}), 400, "invalid_request")
}
