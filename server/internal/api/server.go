// Package api implements the RomSync REST API (prefix /api/v1).
package api

import (
	"database/sql"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/dadoux01/romsync/server/internal/auth"
	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/config"
	"github.com/dadoux01/romsync/server/internal/updates"
)

// Server holds the dependencies of the API handlers.
type Server struct {
	db      *sql.DB
	blobs   *blobs.Store
	cfg     config.Config
	version string
	updates *updates.Relay // nil when the relay is disabled
	now     func() time.Time
	limiter *rateLimiter

	pwParams  auth.Argon2Params
	dummyOnce sync.Once
	dummy     string
}

// Options configures a Server.
type Options struct {
	DB     *sql.DB
	Blobs  *blobs.Store
	Config config.Config
	// Version is the server's version ("dev" for a local build).
	Version string
	// Updates relays the releases to the clients; nil disables it.
	Updates *updates.Relay
	// Now overrides the clock (tests); time.Now when nil.
	Now func() time.Time
	// PasswordParams overrides the Argon2id cost (tests); auth.DefaultParams when zero.
	PasswordParams auth.Argon2Params
}

// New builds the API server.
func New(o Options) *Server {
	now := o.Now
	if now == nil {
		now = time.Now
	}
	version := o.Version
	if version == "" {
		version = "dev"
	}
	pw := o.PasswordParams
	if pw == (auth.Argon2Params{}) {
		pw = auth.DefaultParams
	}
	return &Server{
		db:       o.DB,
		blobs:    o.Blobs,
		cfg:      o.Config,
		version:  version,
		updates:  o.Updates,
		now:      now,
		limiter:  newRateLimiter(5, time.Minute),
		pwParams: pw,
	}
}

// Handler returns the root HTTP handler: the API, and webUI (when not nil)
// for every path outside /api and /healthz.
func (s *Server) Handler(webUI http.Handler) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	r.Use(requestLogger)
	r.Use(securityHeaders)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := s.db.PingContext(r.Context()); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Use(noStore)
		s.routes(r)
		r.NotFound(func(w http.ResponseWriter, r *http.Request) {
			writeError(w, r, errNotFound("unknown route"))
		})
		r.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
			writeError(w, r, newErr(http.StatusMethodNotAllowed, "invalid_request", "method not allowed"))
		})
	})

	if webUI != nil {
		r.NotFound(webUI.ServeHTTP)
	}
	return r
}

// contentSecurityPolicy allows the embedded web UI only: its own scripts
// and styles (inline style attributes included), no framing.
const contentSecurityPolicy = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " +
	"object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "same-origin")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Content-Security-Policy", contentSecurityPolicy)
		next.ServeHTTP(w, r)
	})
}

func noStore(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		slog.Debug("request", "method", r.Method, "path", r.URL.Path,
			"status", ww.Status(), "duration", time.Since(start))
	})
}
