package updates

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Platforms maps each client platform to the end of its release file name
// ("romsync-<version>-<suffix>", see .github/workflows/release.yml).
var Platforms = map[string]string{
	"linux-x64":   "linux-x64.tar.gz",
	"linux-arm64": "linux-arm64.tar.gz",
	"macos":       "macos.zip",
	"windows-x64": "windows-x64.zip",
	"3ds":         "3ds.cia",
}

// Signed files of every release.
const (
	SumsName      = "SHA256SUMS"
	SignatureName = "SHA256SUMS.sig"
)

// AssetName is the file name of a platform's client for a version.
func AssetName(version, platform string) string {
	return "romsync-" + version + "-" + Platforms[platform]
}

// Asset is a file of a release.
type Asset struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
	// apiURL downloads the file through the API (works with a token for a
	// private repository).
	apiURL string
}

// Release is the latest published release (pre-releases excluded).
type Release struct {
	Version     string
	Notes       string
	PublishedAt time.Time
	HTMLURL     string
	Assets      []Asset
}

// Find returns the asset named name.
func (r *Release) Find(name string) (Asset, bool) {
	for _, a := range r.Assets {
		if a.Name == name {
			return a, true
		}
	}
	return Asset{}, false
}

// ErrUnavailable means that no release is known (not checked yet, GitHub
// unreachable, or no release).
var ErrUnavailable = errors.New("no release information")

// ErrNotFound means that a file is not part of the latest release.
var ErrNotFound = errors.New("not a file of the latest release")

// Relay checks the latest release of Repo and serves its files from Dir.
type Relay struct {
	Repo  string // "dadoux01/romsync"
	Token string // optional, for a private fork
	// API is the GitHub API root (tests use a fake server).
	API    string
	Client *http.Client
	Dir    string // cache folder
	// MaxFile bounds the size of a cached file.
	MaxFile int64
	Now     func() time.Time

	mu        sync.Mutex
	latest    *Release
	checkedAt time.Time
	lastErr   error

	dlMu sync.Mutex // one download at a time
}

// NewRelay builds a relay with the defaults.
func NewRelay(repo, token, dir string) *Relay {
	return &Relay{
		Repo:    repo,
		Token:   token,
		API:     "https://api.github.com",
		Client:  &http.Client{Timeout: 5 * time.Minute},
		Dir:     dir,
		MaxFile: 200 << 20,
		Now:     time.Now,
	}
}

// Run checks at once, then every interval, until ctx ends.
func (r *Relay) Run(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		if err := r.Refresh(ctx); err != nil {
			slog.Warn("update check failed", "repo", r.Repo, "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// Latest returns the latest release, when to know, and the error of the
// last check (the previous release is kept when a check fails).
func (r *Relay) Latest() (*Release, time.Time, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.latest == nil {
		err := r.lastErr
		if err == nil {
			err = ErrUnavailable
		}
		return nil, r.checkedAt, err
	}
	return r.latest, r.checkedAt, r.lastErr
}

func (r *Relay) request(ctx context.Context, url, accept string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", accept)
	req.Header.Set("User-Agent", "romsync-server")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	if r.Token != "" {
		req.Header.Set("Authorization", "Bearer "+r.Token)
	}
	return r.Client.Do(req)
}

// Refresh reads the latest release from GitHub.
func (r *Relay) Refresh(ctx context.Context) error {
	rel, err := r.fetchLatest(ctx)
	r.mu.Lock()
	defer r.mu.Unlock()
	r.checkedAt = r.Now()
	r.lastErr = err
	if err == nil {
		r.latest = rel
	}
	return err
}

func (r *Relay) fetchLatest(ctx context.Context) (*Release, error) {
	res, err := r.request(ctx, fmt.Sprintf("%s/repos/%s/releases/latest", r.API, r.Repo), "application/vnd.github+json")
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("%w (repository %s not found, private without token, or no release)", ErrUnavailable, r.Repo)
	}
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub answered %s", res.Status)
	}
	var body struct {
		TagName     string    `json:"tag_name"`
		Body        string    `json:"body"`
		HTMLURL     string    `json:"html_url"`
		PublishedAt time.Time `json:"published_at"`
		Draft       bool      `json:"draft"`
		Prerelease  bool      `json:"prerelease"`
		Assets      []struct {
			Name string `json:"name"`
			Size int64  `json:"size"`
			URL  string `json:"url"`
		} `json:"assets"`
	}
	if err := json.NewDecoder(io.LimitReader(res.Body, 4<<20)).Decode(&body); err != nil {
		return nil, fmt.Errorf("unexpected answer from GitHub: %w", err)
	}
	v, ok := ParseVersion(body.TagName)
	if !ok || body.Draft || body.Prerelease || v.Pre != "" {
		return nil, fmt.Errorf("%w (latest release %q is not a final version)", ErrUnavailable, body.TagName)
	}
	rel := &Release{Version: v.String(), Notes: body.Body, PublishedAt: body.PublishedAt, HTMLURL: body.HTMLURL}
	for _, a := range body.Assets {
		rel.Assets = append(rel.Assets, Asset{Name: a.Name, Size: a.Size, apiURL: a.URL})
	}
	return rel, nil
}

// validName rejects anything that could leave the cache folder.
func validName(s string) bool {
	return s != "" && s != "." && s != ".." && !strings.ContainsAny(s, `/\`) && !strings.HasPrefix(s, ".")
}

// Open returns the cached file name of the latest release (version must be
// the latest one), downloading it first when needed. The caller closes it.
func (r *Relay) Open(ctx context.Context, version, name string) (*os.File, error) {
	rel, _, err := r.Latest()
	if err != nil {
		return nil, err
	}
	a, ok := rel.Find(name)
	if version != rel.Version || !ok || !validName(name) || !validName(version) {
		return nil, ErrNotFound
	}
	path := filepath.Join(r.Dir, version, name)
	if f, err := os.Open(path); err == nil {
		return f, nil
	}

	r.dlMu.Lock()
	defer r.dlMu.Unlock()
	if f, err := os.Open(path); err == nil { // downloaded meanwhile
		return f, nil
	}
	if a.Size > r.MaxFile {
		return nil, fmt.Errorf("%s is too large (%d bytes)", name, a.Size)
	}
	if err := r.download(ctx, a, path); err != nil {
		return nil, err
	}
	r.prune(version)
	return os.Open(path)
}

func (r *Relay) download(ctx context.Context, a Asset, path string) error {
	res, err := r.request(ctx, a.apiURL, "application/octet-stream")
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("downloading %s: GitHub answered %s", a.Name, res.Status)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".download-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	n, err := io.Copy(tmp, io.LimitReader(res.Body, r.MaxFile+1))
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return fmt.Errorf("downloading %s: %w", a.Name, err)
	}
	if n > r.MaxFile || (a.Size > 0 && n != a.Size) {
		return fmt.Errorf("downloading %s: got %d bytes, expected %d", a.Name, n, a.Size)
	}
	return os.Rename(tmp.Name(), path)
}

// prune removes the cached files of other versions.
func (r *Relay) prune(keep string) {
	entries, err := os.ReadDir(r.Dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if e.IsDir() && e.Name() != keep {
			_ = os.RemoveAll(filepath.Join(r.Dir, e.Name()))
		}
	}
}
