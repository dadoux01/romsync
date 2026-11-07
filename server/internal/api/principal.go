package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/dadoux01/romsync/server/internal/auth"
	"github.com/dadoux01/romsync/server/internal/db"
)

const (
	sessionCookie   = "romsync_session"
	sessionLifetime = 30 * 24 * time.Hour
	// sessionRefresh avoids rewriting the session row on every request.
	sessionRefresh = time.Hour
)

// principal is the authenticated caller: a user through a web session, or a
// user's device through its bearer token.
type principal struct {
	UserID      int64
	Username    string
	Role        string
	DeviceID    int64  // 0 for a web session
	SessionHash string // "" for a device
}

func (p *principal) isAdmin() bool   { return p.Role == "admin" }
func (p *principal) isSession() bool { return p.DeviceID == 0 }

type ctxKey struct{}

func principalFrom(ctx context.Context) *principal {
	p, _ := ctx.Value(ctxKey{}).(*principal)
	return p
}

// authKind is the authentication a route requires.
type authKind int

const (
	authSession authKind = iota // web session only
	authAny                     // web session or device token
	authAdmin                   // web session of an admin
)

// require rejects requests that do not satisfy kind.
func (s *Server) require(kind authKind) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			p, err := s.authenticate(r)
			if err != nil {
				writeError(w, r, err)
				return
			}
			if p == nil {
				writeError(w, r, errUnauthorized("authentication required"))
				return
			}
			if kind != authAny && !p.isSession() {
				writeError(w, r, errForbidden("this route requires a web session"))
				return
			}
			if kind == authAdmin && !p.isAdmin() {
				writeError(w, r, errForbidden("administrator only"))
				return
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, p)))
		})
	}
}

// authenticate resolves the caller from the bearer token or the session
// cookie. It returns (nil, nil) for an anonymous request, and an error for
// credentials that are present but invalid.
func (s *Server) authenticate(r *http.Request) (*principal, error) {
	ctx := r.Context()
	now := s.now()
	if h := r.Header.Get("Authorization"); h != "" {
		token, ok := strings.CutPrefix(h, "Bearer ")
		if !ok || token == "" {
			return nil, errUnauthorized("malformed Authorization header")
		}
		var p principal
		err := s.db.QueryRowContext(ctx, `
			SELECT d.id, u.id, u.username, u.role FROM devices d JOIN users u ON u.id = d.user_id
			WHERE d.token_hash = ? AND d.revoked_at IS NULL AND u.disabled_at IS NULL`,
			auth.HashToken(token)).Scan(&p.DeviceID, &p.UserID, &p.Username, &p.Role)
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errUnauthorized("invalid or revoked device token")
		}
		if err != nil {
			return nil, err
		}
		if _, err := s.db.ExecContext(ctx, `UPDATE devices SET last_seen_at = ? WHERE id = ?`,
			db.FormatTime(now), p.DeviceID); err != nil {
			return nil, err
		}
		return &p, nil
	}

	c, _ := r.Cookie(sessionCookie) // the only possible error is http.ErrNoCookie
	if c == nil || c.Value == "" {
		return nil, nil
	}
	p := principal{SessionHash: auth.HashToken(c.Value)}
	var expires string
	err := s.db.QueryRowContext(ctx, `
		SELECT u.id, u.username, u.role, s.expires_at FROM sessions s JOIN users u ON u.id = s.user_id
		WHERE s.token_hash = ? AND u.disabled_at IS NULL`, p.SessionHash).
		Scan(&p.UserID, &p.Username, &p.Role, &expires)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errUnauthorized("session expired")
	}
	if err != nil {
		return nil, err
	}
	exp, err := db.ParseTime(expires)
	if err != nil {
		return nil, err
	}
	if !exp.After(now) {
		_, _ = s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, p.SessionHash)
		return nil, errUnauthorized("session expired")
	}
	// Sliding expiration, written at most once per sessionRefresh.
	if newExp := now.Add(sessionLifetime); newExp.Sub(exp) > sessionRefresh {
		if _, err := s.db.ExecContext(ctx, `UPDATE sessions SET expires_at = ? WHERE token_hash = ?`,
			db.FormatTime(newExp), p.SessionHash); err != nil {
			return nil, err
		}
	}
	return &p, nil
}

// startSession creates a session for userID and sets the cookie.
func (s *Server) startSession(ctx context.Context, q execer, w http.ResponseWriter, r *http.Request, userID int64) error {
	token, hash, err := auth.NewToken()
	if err != nil {
		return err
	}
	now := s.now()
	exp := now.Add(sessionLifetime)
	if _, err := q.ExecContext(ctx, `INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)`,
		hash, userID, db.FormatTime(now), db.FormatTime(exp)); err != nil {
		return err
	}
	// Secure is only set over HTTPS: plain HTTP on the local network is a
	// supported setup, and browsers drop Secure cookies there.
	http.SetCookie(w, &http.Cookie{ //nolint:gosec // see above
		Name:     sessionCookie,
		Value:    token,
		Path:     "/",
		Expires:  exp,
		HttpOnly: true,
		Secure:   s.isHTTPS(r),
		SameSite: http.SameSiteStrictMode,
	})
	return nil
}

func clearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{ //nolint:gosec // an expired, empty cookie
		Name:     sessionCookie,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
	})
}

// isHTTPS reports whether the browser reached us over HTTPS, directly or
// through a trusted proxy such as `tailscale serve`.
func (s *Server) isHTTPS(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return isTrusted(peerAddr(r), s.cfg.TrustedProxies) &&
		strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}

// rateLimit applies the per-IP attempt limit of the specification.
func (s *Server) rateLimit(r *http.Request, bucket string) error {
	if !s.limiter.allow(bucket+"|"+clientIP(r, s.cfg.TrustedProxies), s.now()) {
		return errRateLimited()
	}
	return nil
}

// execer is satisfied by *sql.DB and *sql.Tx.
type execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

// inTx runs fn in a transaction, committing when it returns nil.
func (s *Server) inTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}
