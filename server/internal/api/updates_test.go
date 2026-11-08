package api

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/dadoux01/romsync/server/internal/updates"
)

// fakeReleases serves a v0.5.0 release like the GitHub API.
func fakeReleases(t *testing.T) *httptest.Server {
	files := map[string]string{
		"romsync-0.5.0-3ds.cia":         "cia",
		"romsync-0.5.0-windows-x64.zip": "zip",
		"SHA256SUMS":                    "sums",
		"SHA256SUMS.sig":                "sig",
	}
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/repos/dadoux01/romsync/releases/latest" {
			var assets []map[string]any
			for name, c := range files {
				assets = append(assets, map[string]any{"name": name, "size": len(c), "url": srv.URL + "/assets/" + name})
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"tag_name": "v0.5.0", "body": "notes",
				"html_url": "https://example.test/v0.5.0", "published_at": "2026-11-10T10:00:00Z", "assets": assets})
			return
		}
		if name, ok := strings.CutPrefix(r.URL.Path, "/assets/"); ok {
			_, _ = io.WriteString(w, files[name])
			return
		}
		http.NotFound(w, r)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestServerInfoIsPublic(t *testing.T) {
	e := newTestEnv(t)
	var info struct {
		Version          string `json:"version"`
		APILevel         int    `json:"api_level"`
		MinClientVersion string `json:"min_client_version"`
		Updates          bool   `json:"updates"`
	}
	r := e.client().get("/api/v1/server")
	expect(t, r, 200)
	r.json(t, &info)
	if info.Version != "dev" || info.APILevel != APILevel || info.MinClientVersion != MinClientVersion || info.Updates {
		t.Fatalf("unexpected info %+v", info)
	}
}

func TestUpdateRelay(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	dev, _ := e.pairDevice(admin, "3DS")

	// Disabled relay.
	expectErr(t, dev.get("/api/v1/updates/3ds"), 503, "updates_unavailable")

	gh := fakeReleases(t)
	relay := updates.NewRelay("dadoux01/romsync", "", t.TempDir())
	relay.API = gh.URL
	e.srv.updates = relay
	// Enabled, not checked yet.
	expectErr(t, dev.get("/api/v1/updates/3ds"), 503, "updates_unavailable")
	if err := relay.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}

	// Authentication is required.
	expectErr(t, e.client().get("/api/v1/updates/3ds"), 401, "unauthorized")

	var u struct {
		Version string
		Notes   string
		File    struct {
			Name string
			Size int64
			URL  string
		}
		Sums      struct{ URL string }
		Signature struct{ URL string }
	}
	r := dev.get("/api/v1/updates/3ds")
	expect(t, r, 200)
	r.json(t, &u)
	if u.Version != "0.5.0" || u.Notes != "notes" || u.File.Name != "romsync-0.5.0-3ds.cia" || u.File.Size != 3 ||
		u.Sums.URL != "/api/v1/updates/files/0.5.0/SHA256SUMS" || u.Signature.URL != "/api/v1/updates/files/0.5.0/SHA256SUMS.sig" {
		t.Fatalf("unexpected update %+v", u)
	}

	r = dev.get(u.File.URL)
	expect(t, r, 200)
	if string(r.body) != "cia" {
		t.Fatalf("file content %q", r.body)
	}
	expectErr(t, dev.get("/api/v1/updates/linux-x64"), 404, "not_found") // no asset in this release
	expectErr(t, dev.get("/api/v1/updates/amiga"), 404, "not_found")
	expectErr(t, dev.get("/api/v1/updates/files/0.4.0/SHA256SUMS"), 404, "not_found")
	expectErr(t, dev.get("/api/v1/updates/files/0.5.0/..%2Fromsync.db"), 404, "not_found")

	// The website's banner.
	var info struct {
		ServerVersion string `json:"server_version"`
		Latest        struct{ Version, URL string }
	}
	r = admin.get("/api/v1/updates")
	expect(t, r, 200)
	r.json(t, &info)
	if info.ServerVersion != "dev" || info.Latest.Version != "0.5.0" || info.Latest.URL != "https://example.test/v0.5.0" {
		t.Fatalf("unexpected info %+v", info)
	}
}
