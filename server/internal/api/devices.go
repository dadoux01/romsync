package api

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/dadoux01/romsync/server/internal/auth"
	"github.com/dadoux01/romsync/server/internal/db"
)

// deviceJSON is the public representation of a paired device.
type deviceJSON struct {
	ID          int64   `json:"id"`
	Name        string  `json:"name"`
	Platform    string  `json:"platform"`
	CreatedAt   string  `json:"created_at"`
	LastSeenAt  *string `json:"last_seen_at"`
	RevokedAt   *string `json:"revoked_at"`
	ClockSkewAt *string `json:"clock_skew_at"`
}

const deviceColumns = `id, name, platform, created_at, last_seen_at, revoked_at, clock_skew_at`

func scanDevice(row interface{ Scan(...any) error }) (deviceJSON, error) {
	var d deviceJSON
	err := row.Scan(&d.ID, &d.Name, &d.Platform, &d.CreatedAt, &d.LastSeenAt, &d.RevokedAt, &d.ClockSkewAt)
	return d, err
}

func (s *Server) loadDevice(ctx context.Context, userID, id int64) (deviceJSON, error) {
	d, err := scanDevice(s.db.QueryRowContext(ctx, `SELECT `+deviceColumns+` FROM devices WHERE id = ? AND user_id = ?`, id, userID))
	if errors.Is(err, sql.ErrNoRows) {
		return d, errNotFound("unknown device")
	}
	return d, err
}

const pairCodeTTL = 10 * time.Minute

var platforms = map[string]bool{
	"linux": true, "macos": true, "windows": true, "android": true, "3ds": true, "other": true,
}

// POST /pair-codes
func (s *Server) postPairCode(w http.ResponseWriter, r *http.Request) error {
	code, err := auth.NewPairCode()
	if err != nil {
		return err
	}
	p := principalFrom(r.Context())
	exp := s.now().Add(pairCodeTTL)
	if _, err := s.db.ExecContext(r.Context(), `INSERT INTO pair_codes (code_hash, user_id, expires_at) VALUES (?, ?, ?)`,
		auth.HashToken(auth.NormalizePairCode(code)), p.UserID, db.FormatTime(exp)); err != nil {
		return err
	}
	writeJSON(w, http.StatusCreated, map[string]string{"code": code, "expires_at": db.FormatTime(exp)})
	return nil
}

// POST /pair
func (s *Server) postPair(w http.ResponseWriter, r *http.Request) error {
	if err := s.rateLimit(r, "pair"); err != nil {
		return err
	}
	var req struct {
		Code     string `json:"code"`
		Name     string `json:"name"`
		Platform string `json:"platform"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || utf8.RuneCountInString(req.Name) > 64 {
		return errInvalid("the device name must be 1 to 64 characters")
	}
	if !platforms[req.Platform] {
		return errInvalid("platform must be one of linux, macos, windows, android, 3ds, other")
	}
	code := auth.NormalizePairCode(req.Code)
	if code == "" {
		return errNotFound("unknown pairing code")
	}
	ctx := r.Context()
	var (
		token string
		dev   deviceJSON
	)
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		var (
			userID    int64
			expiresAt string
			usedAt    *string
		)
		codeHash := auth.HashToken(code)
		err := tx.QueryRowContext(ctx, `SELECT p.user_id, p.expires_at, p.used_at FROM pair_codes p
			JOIN users u ON u.id = p.user_id WHERE p.code_hash = ? AND u.disabled_at IS NULL`, codeHash).
			Scan(&userID, &expiresAt, &usedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return errNotFound("unknown pairing code")
		}
		if err != nil {
			return err
		}
		now := db.FormatTime(s.now())
		if usedAt != nil || expiresAt <= now {
			return errExpired("this pairing code has expired or was already used")
		}
		var hash string
		token, hash, err = auth.NewToken()
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE pair_codes SET used_at = ? WHERE code_hash = ?`, now, codeHash); err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO devices (user_id, name, platform, token_hash, created_at, last_seen_at)
			VALUES (?, ?, ?, ?, ?, ?)`, userID, req.Name, req.Platform, hash, now, now)
		if err != nil {
			return err
		}
		id, _ := res.LastInsertId()
		dev, err = scanDevice(tx.QueryRowContext(ctx, `SELECT `+deviceColumns+` FROM devices WHERE id = ?`, id))
		return err
	})
	if err != nil {
		return err
	}
	// The token is only ever returned here; the server keeps its hash.
	writeJSON(w, http.StatusCreated, map[string]any{"token": token, "device": dev})
	return nil
}

// GET /devices
func (s *Server) listDevices(w http.ResponseWriter, r *http.Request) error {
	p := principalFrom(r.Context())
	rows, err := s.db.QueryContext(r.Context(), `SELECT `+deviceColumns+` FROM devices WHERE user_id = ?
		ORDER BY revoked_at IS NOT NULL, id`, p.UserID)
	if err != nil {
		return err
	}
	defer rows.Close()
	devices := []deviceJSON{}
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return err
		}
		devices = append(devices, d)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
	return nil
}

// DELETE /devices/{id}
func (s *Server) deleteDevice(w http.ResponseWriter, r *http.Request) error {
	id, err := pathID(r, "id")
	if err != nil {
		return err
	}
	p := principalFrom(r.Context())
	if _, err := s.loadDevice(r.Context(), p.UserID, id); err != nil {
		return err
	}
	if _, err := s.db.ExecContext(r.Context(), `UPDATE devices SET revoked_at = COALESCE(revoked_at, ?) WHERE id = ?`,
		db.FormatTime(s.now()), id); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}
