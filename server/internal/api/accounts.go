package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/dadoux01/romsync/server/internal/auth"
	"github.com/dadoux01/romsync/server/internal/db"
	"github.com/dadoux01/romsync/server/internal/retention"
)

const (
	minPasswordLen   = 8
	maxPasswordLen   = 256
	inviteDefaultTTL = 7 * 24 * time.Hour
)

var usernameRE = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,32}$`)

// userJSON is the public representation of a user.
type userJSON struct {
	ID              int64            `json:"id"`
	Username        string           `json:"username"`
	Role            string           `json:"role"`
	CreatedAt       string           `json:"created_at"`
	DisabledAt      *string          `json:"disabled_at"`
	RetentionPolicy retention.Policy `json:"retention_policy"`
}

const userColumns = `id, username, role, created_at, disabled_at, retention_policy`

func scanUser(row interface{ Scan(...any) error }) (userJSON, error) {
	var u userJSON
	var policy string
	if err := row.Scan(&u.ID, &u.Username, &u.Role, &u.CreatedAt, &u.DisabledAt, &policy); err != nil {
		return u, err
	}
	p, err := retention.Parse(policy)
	if err != nil {
		return u, err
	}
	u.RetentionPolicy = p
	return u, nil
}

func (s *Server) loadUser(ctx context.Context, q execer, id int64) (userJSON, error) {
	u, err := scanUser(q.QueryRowContext(ctx, `SELECT `+userColumns+` FROM users WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return u, errNotFound("unknown user")
	}
	return u, err
}

type credentials struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func validatePassword(pw string) error {
	if len(pw) < minPasswordLen || len(pw) > maxPasswordLen {
		return errInvalid("the password must be between 8 and 256 characters")
	}
	return nil
}

func (c credentials) validate() error {
	if !usernameRE.MatchString(c.Username) {
		return errInvalid("the username must be 1 to 32 characters among letters, digits, '_', '.' and '-'")
	}
	return validatePassword(c.Password)
}

// createUser inserts a user and returns its id; a taken username is a 409.
func (s *Server) createUser(ctx context.Context, tx *sql.Tx, c credentials, role string) (int64, error) {
	var exists bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE username = ?)`, c.Username).Scan(&exists); err != nil {
		return 0, err
	}
	if exists {
		return 0, errConflict("this username is already taken")
	}
	hash, err := auth.HashPassword(c.Password, s.pwParams)
	if err != nil {
		return 0, err
	}
	res, err := tx.ExecContext(ctx, `INSERT INTO users (username, password_hash, role, created_at, retention_policy)
		VALUES (?, ?, ?, ?, ?)`, c.Username, hash, role, db.FormatTime(s.now()), retention.Default.Encode())
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// GET /setup
func (s *Server) getSetup(w http.ResponseWriter, r *http.Request) error {
	var n int
	if err := s.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM users`).Scan(&n); err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]bool{"needed": n == 0})
	return nil
}

// POST /setup
func (s *Server) postSetup(w http.ResponseWriter, r *http.Request) error {
	if err := s.rateLimit(r, "setup"); err != nil {
		return err
	}
	var c credentials
	if err := decodeJSON(r, &c); err != nil {
		return err
	}
	if err := c.validate(); err != nil {
		return err
	}
	ctx := r.Context()
	var u userJSON
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		var n int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM users`).Scan(&n); err != nil {
			return err
		}
		if n > 0 {
			return errAlreadySetup()
		}
		id, err := s.createUser(ctx, tx, c, "admin")
		if err != nil {
			return err
		}
		if err := s.startSession(ctx, tx, w, r, id); err != nil {
			return err
		}
		u, err = s.loadUser(ctx, tx, id)
		return err
	})
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusCreated, map[string]any{"user": u})
	return nil
}

// dummyHash returns a hash that is verified when the username is unknown, so
// that the response time does not reveal which usernames exist.
func (s *Server) dummyHash() string {
	s.dummyOnce.Do(func() {
		h, err := auth.HashPassword("romsync-dummy-password", s.pwParams)
		if err != nil {
			panic(err)
		}
		s.dummy = h
	})
	return s.dummy
}

// POST /auth/login
func (s *Server) postLogin(w http.ResponseWriter, r *http.Request) error {
	if err := s.rateLimit(r, "login"); err != nil {
		return err
	}
	var c credentials
	if err := decodeJSON(r, &c); err != nil {
		return err
	}
	ctx := r.Context()
	var (
		id       int64
		hash     string
		disabled *string
	)
	err := s.db.QueryRowContext(ctx, `SELECT id, password_hash, disabled_at FROM users WHERE username = ?`, c.Username).
		Scan(&id, &hash, &disabled)
	if errors.Is(err, sql.ErrNoRows) {
		_, _ = auth.VerifyPassword(c.Password, s.dummyHash())
		return errUnauthorized("invalid username or password")
	}
	if err != nil {
		return err
	}
	ok, err := auth.VerifyPassword(c.Password, hash)
	if err != nil {
		return err
	}
	if !ok {
		return errUnauthorized("invalid username or password")
	}
	if disabled != nil {
		return errUnauthorized("this account is disabled")
	}
	if err := s.startSession(ctx, s.db, w, r, id); err != nil {
		return err
	}
	u, err := s.loadUser(ctx, s.db, id)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": u})
	return nil
}

// POST /auth/logout
func (s *Server) postLogout(w http.ResponseWriter, r *http.Request) error {
	p := principalFrom(r.Context())
	if _, err := s.db.ExecContext(r.Context(), `DELETE FROM sessions WHERE token_hash = ?`, p.SessionHash); err != nil {
		return err
	}
	clearSessionCookie(w)
	w.WriteHeader(http.StatusNoContent)
	return nil
}

// GET /me
func (s *Server) getMe(w http.ResponseWriter, r *http.Request) error {
	p := principalFrom(r.Context())
	u, err := s.loadUser(r.Context(), s.db, p.UserID)
	if err != nil {
		return err
	}
	out := map[string]any{"user": u, "device": nil}
	if !p.isSession() {
		d, err := s.loadDevice(r.Context(), p.UserID, p.DeviceID)
		if err != nil {
			return err
		}
		out["device"] = d
	}
	writeJSON(w, http.StatusOK, out)
	return nil
}

// PATCH /me
func (s *Server) patchMe(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		RetentionPolicy *retention.Policy `json:"retention_policy"`
		CurrentPassword *string           `json:"current_password"`
		NewPassword     *string           `json:"new_password"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	p := principalFrom(r.Context())
	ctx := r.Context()
	if req.RetentionPolicy != nil {
		if err := req.RetentionPolicy.Validate(); err != nil {
			return errInvalid(err.Error())
		}
	}
	if req.NewPassword != nil {
		if err := validatePassword(*req.NewPassword); err != nil {
			return err
		}
		if req.CurrentPassword == nil {
			return errInvalid("current_password is required to change the password")
		}
		var hash string
		if err := s.db.QueryRowContext(ctx, `SELECT password_hash FROM users WHERE id = ?`, p.UserID).Scan(&hash); err != nil {
			return err
		}
		ok, err := auth.VerifyPassword(*req.CurrentPassword, hash)
		if err != nil {
			return err
		}
		if !ok {
			return errForbidden("the current password is incorrect")
		}
	}
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		if req.RetentionPolicy != nil {
			if _, err := tx.ExecContext(ctx, `UPDATE users SET retention_policy = ? WHERE id = ?`,
				req.RetentionPolicy.Encode(), p.UserID); err != nil {
				return err
			}
		}
		if req.NewPassword != nil {
			hash, err := auth.HashPassword(*req.NewPassword, s.pwParams)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE users SET password_hash = ? WHERE id = ?`, hash, p.UserID); err != nil {
				return err
			}
			// Other browsers lose their session; this one stays signed in.
			if _, err := tx.ExecContext(ctx, `DELETE FROM sessions WHERE user_id = ? AND token_hash <> ?`,
				p.UserID, p.SessionHash); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	u, err := s.loadUser(ctx, s.db, p.UserID)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": u})
	return nil
}

// GET /users
func (s *Server) listUsers(w http.ResponseWriter, r *http.Request) error {
	rows, err := s.db.QueryContext(r.Context(), `SELECT `+userColumns+` FROM users ORDER BY id`)
	if err != nil {
		return err
	}
	defer rows.Close()
	users := []userJSON{}
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return err
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": users})
	return nil
}

func pathID(r *http.Request, name string) (int64, error) {
	id, err := strconv.ParseInt(chi.URLParam(r, name), 10, 64)
	if err != nil || id < 1 {
		return 0, errNotFound("unknown " + name)
	}
	return id, nil
}

// PATCH /users/{id}
func (s *Server) patchUser(w http.ResponseWriter, r *http.Request) error {
	id, err := pathID(r, "id")
	if err != nil {
		return err
	}
	var req struct {
		Disabled *bool   `json:"disabled"`
		Password *string `json:"password"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	p := principalFrom(r.Context())
	if req.Disabled != nil && *req.Disabled && id == p.UserID {
		return errForbidden("you cannot disable your own account")
	}
	if req.Password != nil {
		if err := validatePassword(*req.Password); err != nil {
			return err
		}
	}
	ctx := r.Context()
	err = s.inTx(ctx, func(tx *sql.Tx) error {
		if _, err := s.loadUser(ctx, tx, id); err != nil {
			return err
		}
		if req.Disabled != nil {
			var disabledAt any
			if *req.Disabled {
				disabledAt = db.FormatTime(s.now())
			}
			if _, err := tx.ExecContext(ctx, `UPDATE users SET disabled_at = ? WHERE id = ?`, disabledAt, id); err != nil {
				return err
			}
		}
		if req.Password != nil {
			hash, err := auth.HashPassword(*req.Password, s.pwParams)
			if err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE users SET password_hash = ? WHERE id = ?`, hash, id); err != nil {
				return err
			}
		}
		if (req.Disabled != nil && *req.Disabled) || req.Password != nil {
			if _, err := tx.ExecContext(ctx, `DELETE FROM sessions WHERE user_id = ?`, id); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	u, err := s.loadUser(ctx, s.db, id)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": u})
	return nil
}

type inviteJSON struct {
	ID         int64   `json:"id"`
	CreatedBy  int64   `json:"created_by"`
	CreatedAt  string  `json:"created_at"`
	ExpiresAt  string  `json:"expires_at"`
	UsedBy     *int64  `json:"used_by"`
	UsedByName *string `json:"used_by_username"`
	UsedAt     *string `json:"used_at"`
	Status     string  `json:"status"` // pending, used, expired
}

// loadInvites returns every invitation, or only the one with id when id > 0.
func (s *Server) loadInvites(ctx context.Context, id int64) ([]inviteJSON, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT i.id, i.created_by, i.created_at, i.expires_at, i.used_by, u.username, i.used_at
		FROM invites i LEFT JOIN users u ON u.id = i.used_by WHERE ? = 0 OR i.id = ? ORDER BY i.id DESC`, id, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	now := db.FormatTime(s.now())
	out := []inviteJSON{}
	for rows.Next() {
		var i inviteJSON
		if err := rows.Scan(&i.ID, &i.CreatedBy, &i.CreatedAt, &i.ExpiresAt, &i.UsedBy, &i.UsedByName, &i.UsedAt); err != nil {
			return nil, err
		}
		switch {
		case i.UsedAt != nil:
			i.Status = "used"
		case i.ExpiresAt <= now:
			i.Status = "expired"
		default:
			i.Status = "pending"
		}
		out = append(out, i)
	}
	return out, rows.Err()
}

// GET /invites
func (s *Server) listInvites(w http.ResponseWriter, r *http.Request) error {
	invites, err := s.loadInvites(r.Context(), 0)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"invites": invites})
	return nil
}

// POST /invites
func (s *Server) postInvite(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		ExpiresInDays *int `json:"expires_in_days"`
	}
	if r.ContentLength != 0 {
		if err := decodeJSON(r, &req); err != nil {
			return err
		}
	}
	ttl := inviteDefaultTTL
	if req.ExpiresInDays != nil {
		if *req.ExpiresInDays < 1 || *req.ExpiresInDays > 30 {
			return errInvalid("expires_in_days must be between 1 and 30")
		}
		ttl = time.Duration(*req.ExpiresInDays) * 24 * time.Hour
	}
	token, hash, err := auth.NewToken()
	if err != nil {
		return err
	}
	p := principalFrom(r.Context())
	now := s.now()
	res, err := s.db.ExecContext(r.Context(), `INSERT INTO invites (token_hash, created_by, created_at, expires_at) VALUES (?, ?, ?, ?)`,
		hash, p.UserID, db.FormatTime(now), db.FormatTime(now.Add(ttl)))
	if err != nil {
		return err
	}
	id, _ := res.LastInsertId()
	invites, err := s.loadInvites(r.Context(), id)
	if err != nil {
		return err
	}
	// The token is only ever returned here; the server keeps its hash.
	writeJSON(w, http.StatusCreated, map[string]any{"invite": invites[0], "token": token})
	return nil
}

// POST /invites/{token}/accept
func (s *Server) acceptInvite(w http.ResponseWriter, r *http.Request) error {
	if err := s.rateLimit(r, "invite"); err != nil {
		return err
	}
	var c credentials
	if err := decodeJSON(r, &c); err != nil {
		return err
	}
	if err := c.validate(); err != nil {
		return err
	}
	ctx := r.Context()
	hash := auth.HashToken(chi.URLParam(r, "token"))
	var u userJSON
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		var (
			inviteID  int64
			expiresAt string
			usedAt    *string
		)
		err := tx.QueryRowContext(ctx, `SELECT id, expires_at, used_at FROM invites WHERE token_hash = ?`, hash).
			Scan(&inviteID, &expiresAt, &usedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return errNotFound("unknown invitation")
		}
		if err != nil {
			return err
		}
		now := s.now()
		if usedAt != nil || expiresAt <= db.FormatTime(now) {
			return errExpired("this invitation has expired or was already used")
		}
		id, err := s.createUser(ctx, tx, c, "user")
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE invites SET used_by = ?, used_at = ? WHERE id = ?`,
			id, db.FormatTime(now), inviteID); err != nil {
			return err
		}
		if err := s.startSession(ctx, tx, w, r, id); err != nil {
			return err
		}
		u, err = s.loadUser(ctx, tx, id)
		return err
	})
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusCreated, map[string]any{"user": u})
	return nil
}
