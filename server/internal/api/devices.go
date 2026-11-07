package api

import (
	"context"
	"database/sql"
	"errors"
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
