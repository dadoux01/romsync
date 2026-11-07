package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/dadoux01/romsync/server/internal/auth"
	"github.com/dadoux01/romsync/server/internal/config"
	"github.com/dadoux01/romsync/server/internal/db"
)

// testClock is a controllable clock shared by the server under test.
type testClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *testClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *testClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

type testEnv struct {
	t     *testing.T
	srv   *Server
	http  *httptest.Server
	clock *testClock
	cfg   config.Config
}

func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	dir := t.TempDir()
	conn, err := db.Open(context.Background(), filepath.Join(dir, "romsync.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })

	cfg := config.Defaults()
	cfg.DataDir = dir
	cfg.MaxUpload = 1 << 20
	clock := &testClock{t: time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC)}
	srv := New(Options{DB: conn, Config: cfg, Now: clock.Now,
		PasswordParams: auth.Argon2Params{Memory: 1024, Time: 1, Threads: 1, KeyLen: 32, SaltLen: 16}})
	hs := httptest.NewServer(srv.Handler(nil))
	t.Cleanup(hs.Close)
	return &testEnv{t: t, srv: srv, http: hs, clock: clock, cfg: cfg}
}

// client is an HTTP client with its own cookie jar and optional bearer token.
type client struct {
	env   *testEnv
	hc    *http.Client
	token string
}

func (e *testEnv) client() *client {
	jar, _ := cookiejar.New(nil)
	return &client{env: e, hc: &http.Client{Jar: jar}}
}

type response struct {
	status int
	header http.Header
	body   []byte
}

func (r response) json(t *testing.T, dst any) {
	t.Helper()
	if err := json.Unmarshal(r.body, dst); err != nil {
		t.Fatalf("decoding %q: %v", r.body, err)
	}
}

// errCode returns the error code of an error response ("" if none).
func (r response) errCode() string {
	var b errorBody
	if json.Unmarshal(r.body, &b) != nil {
		return ""
	}
	return b.Error.Code
}

func (c *client) do(method, path string, body io.Reader, headers map[string]string) response {
	c.env.t.Helper()
	req, err := http.NewRequest(method, c.env.http.URL+path, body)
	if err != nil {
		c.env.t.Fatal(err)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	res, err := c.hc.Do(req)
	if err != nil {
		c.env.t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return response{status: res.StatusCode, header: res.Header, body: b}
}

func (c *client) jsonReq(method, path string, v any) response {
	c.env.t.Helper()
	var body io.Reader
	h := map[string]string{}
	if v != nil {
		b, err := json.Marshal(v)
		if err != nil {
			c.env.t.Fatal(err)
		}
		body = bytes.NewReader(b)
		h["Content-Type"] = "application/json"
	}
	return c.do(method, path, body, h)
}

func (c *client) get(path string) response          { return c.jsonReq(http.MethodGet, path, nil) }
func (c *client) post(path string, v any) response  { return c.jsonReq(http.MethodPost, path, v) }
func (c *client) patch(path string, v any) response { return c.jsonReq(http.MethodPatch, path, v) }
func (c *client) delete(path string) response       { return c.jsonReq(http.MethodDelete, path, nil) }

// expect fails the test when the response status differs from want.
func expect(t *testing.T, r response, want int) {
	t.Helper()
	if r.status != want {
		t.Fatalf("expected status %d, got %d: %s", want, r.status, r.body)
	}
}

// expectErr fails the test unless the response is the given API error.
func expectErr(t *testing.T, r response, status int, code string) {
	t.Helper()
	if r.status != status || r.errCode() != code {
		t.Fatalf("expected %d %s, got %d: %s", status, code, r.status, r.body)
	}
}
