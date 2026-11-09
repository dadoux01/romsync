package updates

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestParseAndCompareVersions(t *testing.T) {
	for _, bad := range []string{"", "1.2", "1.2.3.4", "a.b.c", "1.02.3", "1.2.3-", "dev"} {
		if _, ok := ParseVersion(bad); ok {
			t.Errorf("%q should be refused", bad)
		}
	}
	order := []string{"0.4.0", "0.5.0-rc1", "0.5.0-rc2", "v0.5.0", "0.5.1", "0.10.0", "1.0.0"}
	for i := 0; i+1 < len(order); i++ {
		a, ok1 := ParseVersion(order[i])
		b, ok2 := ParseVersion(order[i+1])
		if !ok1 || !ok2 || a.Compare(b) != -1 || b.Compare(a) != 1 || a.Compare(a) != 0 {
			t.Errorf("%s < %s expected", order[i], order[i+1])
		}
	}
	if v, _ := ParseVersion("v0.5.0-rc1"); v.String() != "0.5.0-rc1" {
		t.Errorf("String() = %s", v)
	}
}

// fakeGitHub serves one release of dadoux01/romsync.
type fakeGitHub struct {
	srv       *httptest.Server
	release   map[string]any
	files     map[string]string
	token     string // required when set
	downloads atomic.Int32
	checks    atomic.Int32 // requests of the latest release
}

func newFakeGitHub(t *testing.T) *fakeGitHub {
	g := &fakeGitHub{files: map[string]string{
		"romsync-0.5.0-3ds.cia":         "cia content",
		"romsync-0.5.0-windows-x64.zip": "zip content",
		"SHA256SUMS":                    "sums",
		"SHA256SUMS.sig":                "sig",
	}}
	g.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if g.token != "" && r.Header.Get("Authorization") != "Bearer "+g.token {
			http.NotFound(w, r)
			return
		}
		if r.URL.Path == "/repos/dadoux01/romsync/releases/latest" {
			g.checks.Add(1)
			if g.release == nil {
				http.NotFound(w, r)
				return
			}
			_ = json.NewEncoder(w).Encode(g.release)
			return
		}
		if name, ok := strings.CutPrefix(r.URL.Path, "/assets/"); ok && r.Header.Get("Accept") == "application/octet-stream" {
			g.downloads.Add(1)
			_, _ = io.WriteString(w, g.files[name])
			return
		}
		http.NotFound(w, r)
	}))
	t.Cleanup(g.srv.Close)
	assets := []map[string]any{}
	for name, content := range g.files {
		assets = append(assets, map[string]any{"name": name, "size": len(content), "url": g.srv.URL + "/assets/" + name})
	}
	g.release = map[string]any{"tag_name": "v0.5.0", "body": "## Updating\nServer first.", "html_url": "https://github.com/dadoux01/romsync/releases/tag/v0.5.0",
		"published_at": "2026-11-10T10:00:00Z", "draft": false, "prerelease": false, "assets": assets}
	return g
}

func newTestRelay(t *testing.T, g *fakeGitHub) *Relay {
	r := NewRelay("dadoux01/romsync", "", t.TempDir())
	r.API = g.srv.URL
	return r
}

func TestRelayReadsTheLatestReleaseAndCachesItsFiles(t *testing.T) {
	g := newFakeGitHub(t)
	r := newTestRelay(t, g)
	if _, _, err := r.Latest(); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("before a check: %v", err)
	}
	if err := r.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	rel, _, err := r.Latest()
	if err != nil || rel.Version != "0.5.0" || !strings.Contains(rel.Notes, "Server first") || len(rel.Assets) != 4 {
		t.Fatalf("latest = %+v, %v", rel, err)
	}

	for i := 0; i < 2; i++ {
		f, err := r.Open(context.Background(), "0.5.0", "romsync-0.5.0-3ds.cia")
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(f)
		f.Close()
		if string(b) != "cia content" {
			t.Fatalf("content %q", b)
		}
	}
	if n := g.downloads.Load(); n != 1 {
		t.Fatalf("%d downloads, want 1 (cached)", n)
	}

	// Only files of the latest release, and no path tricks.
	for _, c := range [][2]string{{"0.4.0", "romsync-0.5.0-3ds.cia"}, {"0.5.0", "other.zip"}, {"0.5.0", "../../etc/passwd"}, {"..", "SHA256SUMS"}} {
		if _, err := r.Open(context.Background(), c[0], c[1]); !errors.Is(err, ErrNotFound) {
			t.Errorf("Open(%q, %q) = %v, want ErrNotFound", c[0], c[1], err)
		}
	}
}

func TestRelayKeepsTheLastReleaseWhenACheckFails(t *testing.T) {
	g := newFakeGitHub(t)
	r := newTestRelay(t, g)
	if err := r.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	g.release = nil
	if err := r.Refresh(context.Background()); err == nil {
		t.Fatal("expected an error")
	}
	if rel, _, err := r.Latest(); rel == nil || rel.Version != "0.5.0" || err == nil {
		t.Fatalf("latest = %v, %v", rel, err)
	}
}

func TestRelayIgnoresPreReleasesAndUsesTheToken(t *testing.T) {
	g := newFakeGitHub(t)
	g.release["tag_name"] = "v0.6.0-rc1"
	r := newTestRelay(t, g)
	if err := r.Refresh(context.Background()); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("pre-release: %v", err)
	}

	g.release["tag_name"] = "v0.5.0"
	g.token = "secret"
	if err := r.Refresh(context.Background()); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("private without token: %v", err)
	}
	r.Token = "secret"
	if err := r.Refresh(context.Background()); err != nil {
		t.Fatalf("with token: %v", err)
	}
	f, err := r.Open(context.Background(), "0.5.0", "SHA256SUMS")
	if err != nil {
		t.Fatal(err)
	}
	f.Close()
}

func TestRelayRefusesATruncatedDownloadAndPrunesOldVersions(t *testing.T) {
	g := newFakeGitHub(t)
	r := newTestRelay(t, g)
	old := filepath.Join(r.Dir, "0.4.0")
	if err := os.MkdirAll(old, 0o750); err != nil {
		t.Fatal(err)
	}
	_ = r.Refresh(context.Background())
	g.files["SHA256SUMS"] = "su" // shorter than announced
	if _, err := r.Open(context.Background(), "0.5.0", "SHA256SUMS"); err == nil {
		t.Fatal("a truncated file must be refused")
	}
	if _, err := os.Stat(filepath.Join(r.Dir, "0.5.0", "SHA256SUMS")); err == nil {
		t.Fatal("a refused file must not be cached")
	}
	f, err := r.Open(context.Background(), "0.5.0", "SHA256SUMS.sig")
	if err != nil {
		t.Fatal(err)
	}
	f.Close()
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatal("older versions must be pruned")
	}
}

// A release published since the last check is seen as soon as a client
// asks, once the knowledge is older than maxAge; GitHub is not asked again
// within maxAge, even when it fails.
func TestLatestFreshChecksAgainWhenStale(t *testing.T) {
	g := newFakeGitHub(t)
	r := newTestRelay(t, g)
	now := time.Date(2026, 11, 9, 0, 0, 0, 0, time.UTC)
	r.Now = func() time.Time { return now }

	rel, _, err := r.LatestFresh(context.Background(), 10*time.Minute) // never checked: checks
	if err != nil || rel.Version != "0.5.0" || g.checks.Load() != 1 {
		t.Fatalf("first: %v %v, %d checks", rel, err, g.checks.Load())
	}

	g.release["tag_name"] = "v0.5.1" // published after the check
	now = now.Add(5 * time.Minute)
	rel, _, _ = r.LatestFresh(context.Background(), 10*time.Minute)
	if rel.Version != "0.5.0" || g.checks.Load() != 1 {
		t.Fatalf("within maxAge: %s, %d checks", rel.Version, g.checks.Load())
	}
	now = now.Add(6 * time.Minute)
	rel, _, _ = r.LatestFresh(context.Background(), 10*time.Minute)
	if rel.Version != "0.5.1" || g.checks.Load() != 2 {
		t.Fatalf("stale: %s, %d checks", rel.Version, g.checks.Load())
	}

	// GitHub fails: the known release stays, and is not asked again at once.
	g.release = nil
	now = now.Add(11 * time.Minute)
	rel, _, err = r.LatestFresh(context.Background(), 10*time.Minute)
	if rel == nil || rel.Version != "0.5.1" || err == nil || g.checks.Load() != 3 {
		t.Fatalf("failed check: %v %v, %d checks", rel, err, g.checks.Load())
	}
	_, _, _ = r.LatestFresh(context.Background(), 10*time.Minute)
	if g.checks.Load() != 3 {
		t.Fatalf("a failed check must count: %d checks", g.checks.Load())
	}
}
