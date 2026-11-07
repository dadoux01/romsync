package api

import (
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"
	"time"
)

func TestHealthz(t *testing.T) {
	e := newTestEnv(t)
	r := e.client().get("/healthz")
	expect(t, r, http.StatusOK)
}

func TestUnknownRouteUsesErrorFormat(t *testing.T) {
	e := newTestEnv(t)
	r := e.client().get("/api/v1/does-not-exist")
	expectErr(t, r, http.StatusNotFound, "not_found")
	if ct := r.header.Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Fatalf("unexpected content type %q", ct)
	}
}

func TestClientIP(t *testing.T) {
	trusted := []netip.Prefix{netip.MustParsePrefix("127.0.0.1/32")}
	req := func(remote, xff string) *http.Request {
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		r.RemoteAddr = remote
		if xff != "" {
			r.Header.Set("X-Forwarded-For", xff)
		}
		return r
	}
	cases := []struct {
		name, remote, xff string
		trusted           []netip.Prefix
		want              string
	}{
		{"no proxy configured ignores header", "127.0.0.1:1234", "10.0.0.9", nil, "127.0.0.1"},
		{"untrusted peer ignores header", "192.168.1.5:1234", "10.0.0.9", trusted, "192.168.1.5"},
		{"trusted peer uses header", "127.0.0.1:1234", "10.0.0.9", trusted, "10.0.0.9"},
		{"spoofed left-most entry is ignored", "127.0.0.1:1234", "6.6.6.6, 10.0.0.9", trusted, "10.0.0.9"},
		{"trusted peer without header", "127.0.0.1:1234", "", trusted, "127.0.0.1"},
		{"garbage header falls back to peer", "127.0.0.1:1234", "nope", trusted, "127.0.0.1"},
	}
	for _, c := range cases {
		if got := clientIP(req(c.remote, c.xff), c.trusted); got != c.want {
			t.Errorf("%s: got %s, want %s", c.name, got, c.want)
		}
	}
}

func TestRateLimiter(t *testing.T) {
	l := newRateLimiter(5, time.Minute)
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	for i := 0; i < 5; i++ {
		if !l.allow("a", now) {
			t.Fatalf("attempt %d should be allowed", i+1)
		}
	}
	if l.allow("a", now) {
		t.Fatal("6th attempt should be refused")
	}
	if !l.allow("b", now) {
		t.Fatal("another key must not be limited")
	}
	if !l.allow("a", now.Add(time.Minute+time.Second)) {
		t.Fatal("attempts must be allowed again after the window")
	}
}
