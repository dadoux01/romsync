// Package api implements the RomSync REST API (prefix /api/v1).
package api

import (
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/dadoux01/romsync/server/internal/config"
)

// Server holds the dependencies of the API handlers.
type Server struct {
	db      *sql.DB
	cfg     config.Config
	now     func() time.Time
	limiter *rateLimiter
}

// Options configures a Server.
type Options struct {
	DB     *sql.DB
	Config config.Config
	// Now overrides the clock (tests); time.Now when nil.
	Now func() time.Time
}

// New builds the API server.
func New(o Options) *Server {
	now := o.Now
	if now == nil {
		now = time.Now
	}
	return &Server{
		db:      o.DB,
		cfg:     o.Config,
		now:     now,
		limiter: newRateLimiter(5, time.Minute),
	}
}

// Handler returns the root HTTP handler: the API, and webUI (when not nil)
// for every path outside /api and /healthz.
func (s *Server) Handler(webUI http.Handler) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	r.Use(requestLogger)

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
