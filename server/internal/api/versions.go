package api

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/dadoux01/romsync/server/internal/blobs"
	"github.com/dadoux01/romsync/server/internal/convert"
	"github.com/dadoux01/romsync/server/internal/db"
	"github.com/dadoux01/romsync/server/internal/syncrule"
)

// versionJSON is the public representation of a save version.
type versionJSON struct {
	ID              int64   `json:"id"`
	GameCode        string  `json:"game_code"`
	SHA256          string  `json:"sha256"`
	Size            int64   `json:"size"`
	SavedAt         string  `json:"saved_at"`
	SavedAtReported *string `json:"saved_at_reported"`
	UploadedAt      string  `json:"uploaded_at"`
	DeviceID        *int64  `json:"device_id"`
	DeviceName      *string `json:"device_name"`
	Emulator        string  `json:"emulator"`
	BaseVersionID   *int64  `json:"base_version_id"`
	IsActive        bool    `json:"is_active"`
	Conflict        bool    `json:"conflict"`
	Pinned          bool    `json:"pinned"`
	Note            string  `json:"note"`
}

const versionSelect = `SELECT v.id, g.game_code, v.blob_hash, v.size, v.saved_at, v.saved_at_reported, v.uploaded_at,
	v.device_id, d.name, v.emulator, v.base_version_id, v.is_active, v.conflict, v.pinned, v.note
	FROM save_versions v JOIN games g ON g.id = v.game_id LEFT JOIN devices d ON d.id = v.device_id`

func scanVersion(row interface{ Scan(...any) error }) (versionJSON, error) {
	var v versionJSON
	err := row.Scan(&v.ID, &v.GameCode, &v.SHA256, &v.Size, &v.SavedAt, &v.SavedAtReported, &v.UploadedAt,
		&v.DeviceID, &v.DeviceName, &v.Emulator, &v.BaseVersionID, &v.IsActive, &v.Conflict, &v.Pinned, &v.Note)
	return v, err
}

func (s *Server) activeVersion(ctx context.Context, q execer, gameID int64) (*versionJSON, error) {
	v, err := scanVersion(q.QueryRowContext(ctx, versionSelect+` WHERE v.game_id = ? AND v.is_active = 1`, gameID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// loadVersion returns a version of the user's account, or a 404.
func (s *Server) loadVersion(ctx context.Context, q execer, userID, id int64) (versionJSON, int64, error) {
	var gameID int64
	row := q.QueryRowContext(ctx, `SELECT v.game_id FROM save_versions v JOIN games g ON g.id = v.game_id
		WHERE v.id = ? AND g.user_id = ?`, id, userID)
	if err := row.Scan(&gameID); errors.Is(err, sql.ErrNoRows) {
		return versionJSON{}, 0, errNotFound("unknown version")
	} else if err != nil {
		return versionJSON{}, 0, err
	}
	v, err := scanVersion(q.QueryRowContext(ctx, versionSelect+` WHERE v.id = ?`, id))
	return v, gameID, err
}

// GET /games/{code}/active
func (s *Server) getActive(w http.ResponseWriter, r *http.Request) error {
	code, err := gameCodeParam(r)
	if err != nil {
		return err
	}
	ctx := r.Context()
	g, err := s.loadGame(ctx, s.db, principalFrom(ctx).UserID, code)
	if err != nil {
		return err
	}
	if g.ActiveVersion == nil {
		return errNotFound("this game has no active version")
	}
	writeJSON(w, http.StatusOK, map[string]any{"version": g.ActiveVersion})
	return nil
}

// GET /games/{code}/versions?limit=50&before=<id>
func (s *Server) listVersions(w http.ResponseWriter, r *http.Request) error {
	code, err := gameCodeParam(r)
	if err != nil {
		return err
	}
	limit := 50
	if v := r.URL.Query().Get("limit"); v != "" {
		limit, err = strconv.Atoi(v)
		if err != nil || limit < 1 || limit > 200 {
			return errInvalid("limit must be between 1 and 200")
		}
	}
	ctx := r.Context()
	userID := principalFrom(ctx).UserID
	g, err := s.loadGame(ctx, s.db, userID, code)
	if err != nil {
		return err
	}

	query := versionSelect + ` WHERE v.game_id = ?`
	args := []any{g.ID}
	if v := r.URL.Query().Get("before"); v != "" {
		beforeID, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			return errInvalid("invalid before cursor")
		}
		var savedAt string
		err = s.db.QueryRowContext(ctx, `SELECT saved_at FROM save_versions WHERE id = ? AND game_id = ?`, beforeID, g.ID).Scan(&savedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return errInvalid("unknown before cursor")
		}
		if err != nil {
			return err
		}
		query += ` AND (v.saved_at < ? OR (v.saved_at = ? AND v.id < ?))`
		args = append(args, savedAt, savedAt, beforeID)
	}
	query += ` ORDER BY v.saved_at DESC, v.id DESC LIMIT ?`
	args = append(args, limit+1)

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	versions := []versionJSON{}
	for rows.Next() {
		v, err := scanVersion(rows)
		if err != nil {
			return err
		}
		versions = append(versions, v)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	var next *int64
	if len(versions) > limit {
		versions = versions[:limit]
		id := versions[limit-1].ID
		next = &id
	}
	writeJSON(w, http.StatusOK, map[string]any{"versions": versions, "next_before": next})
	return nil
}

var uploadIDRE = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// uploadRequest holds the validated headers of an upload.
type uploadRequest struct {
	uploadID  string
	savedAt   time.Time
	base      *int64
	emulator  string
	sha256    string
	title     string
	forceSize bool
}

func parseUploadHeaders(r *http.Request) (uploadRequest, error) {
	var u uploadRequest
	h := r.Header
	u.uploadID = h.Get("X-Upload-Id")
	if !uploadIDRE.MatchString(u.uploadID) {
		return u, errInvalid("X-Upload-Id must be 1 to 64 characters among letters, digits, '_' and '-'")
	}
	t, err := time.Parse(time.RFC3339Nano, h.Get("X-Saved-At"))
	if err != nil {
		return u, errInvalid("X-Saved-At must be an ISO 8601 date with a time zone")
	}
	u.savedAt = t.UTC()
	if v := strings.TrimSpace(h.Get("X-Base-Version")); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil || id < 1 {
			return u, errInvalid("X-Base-Version must be a version id or empty")
		}
		u.base = &id
	}
	u.emulator = strings.TrimSpace(h.Get("X-Emulator"))
	if utf8.RuneCountInString(u.emulator) > 64 {
		return u, errInvalid("X-Emulator must be at most 64 characters")
	}
	u.sha256 = strings.ToLower(strings.TrimSpace(h.Get("X-Content-SHA256")))
	if !blobs.ValidHash(u.sha256) {
		return u, errInvalid("X-Content-SHA256 must be a hex SHA-256")
	}
	// The title is percent-encoded, since browsers only send Latin-1 headers.
	if v := h.Get("X-Game-Title"); v != "" {
		dec, err := url.PathUnescape(v)
		if err != nil {
			return u, errInvalid("X-Game-Title must be percent-encoded UTF-8")
		}
		if u.title, err = validTitle(dec); err != nil {
			return u, err
		}
	}
	switch strings.ToLower(h.Get("X-Force-Size")) {
	case "", "false":
	case "true":
		u.forceSize = true
	default:
		return u, errInvalid("X-Force-Size must be true or false")
	}
	return u, nil
}

// readBody reads the request body within the upload limit.
func (s *Server) readBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	if r.ContentLength > s.cfg.MaxUpload {
		return nil, errTooLarge()
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, s.cfg.MaxUpload))
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		return nil, errTooLarge()
	}
	if err != nil {
		return nil, errInvalid("could not read the request body")
	}
	return data, nil
}

type uploadResult struct {
	Version  versionJSON `json:"version"`
	Created  bool        `json:"created"`
	Active   bool        `json:"active"`
	Conflict bool        `json:"conflict"`
}

// POST /games/{code}/versions
func (s *Server) postVersion(w http.ResponseWriter, r *http.Request) error {
	code, err := gameCodeParam(r)
	if err != nil {
		return err
	}
	req, err := parseUploadHeaders(r)
	if err != nil {
		return err
	}
	ctx := r.Context()
	p := principalFrom(ctx)
	if req.forceSize && !p.isSession() {
		return errForbidden("X-Force-Size is only accepted from the web interface")
	}
	body, err := s.readBody(w, r)
	if err != nil {
		return err
	}
	if blobs.Sum(body) != req.sha256 {
		return errHashMismatch()
	}
	data, err := s.decodeUpload(r, body)
	if err != nil {
		return err
	}
	if len(data) == 0 {
		return errInvalid("the save is empty")
	}

	var (
		res    uploadResult
		status = http.StatusCreated
	)
	err = s.blobs.Use(func() error {
		hash, err := s.blobs.Put(data)
		if err != nil {
			return err
		}
		return s.inTx(ctx, func(tx *sql.Tx) error {
			// Idempotence: a retried upload returns the original response.
			var prevID int64
			var prevCode string
			err := tx.QueryRowContext(ctx, `SELECT v.id, g.game_code FROM save_versions v JOIN games g ON g.id = v.game_id
				WHERE g.user_id = ? AND v.upload_id = ?`, p.UserID, req.uploadID).Scan(&prevID, &prevCode)
			if err == nil {
				if prevCode != code {
					return errConflict("this X-Upload-Id was already used for another game")
				}
				v, _, err := s.loadVersion(ctx, tx, p.UserID, prevID)
				if err != nil {
					return err
				}
				res = uploadResult{Version: v, Created: true, Active: v.IsActive, Conflict: v.Conflict}
				return nil
			}
			if !errors.Is(err, sql.ErrNoRows) {
				return err
			}

			now := s.now()
			g, err := s.loadOrCreateGame(ctx, tx, p.UserID, code, req.title, now)
			if err != nil {
				return err
			}

			// Same content as the active version: nothing to do.
			if g.ActiveVersion != nil && g.ActiveVersion.SHA256 == hash {
				res = uploadResult{Version: *g.ActiveVersion, Active: true}
				status = http.StatusOK
				return nil
			}

			size := int64(len(data))
			if g.ChipSize != nil && *g.ChipSize != size {
				if !req.forceSize {
					return errSizeMismatch(fmt.Sprintf("this game's saves are %d bytes, got %d", *g.ChipSize, size))
				}
			}
			if g.ChipSize == nil || *g.ChipSize != size {
				if _, err := tx.ExecContext(ctx, `UPDATE games SET chip_size = ? WHERE id = ?`, size, g.ID); err != nil {
					return err
				}
			}

			savedAt, skewed := syncrule.ClampSavedAt(req.savedAt, now)
			var reported any
			if skewed {
				reported = db.FormatTime(req.savedAt)
				if !p.isSession() {
					if _, err := tx.ExecContext(ctx, `UPDATE devices SET clock_skew_at = ? WHERE id = ?`,
						db.FormatTime(now), p.DeviceID); err != nil {
						return err
					}
				}
			}

			var active *syncrule.Active
			if g.ActiveVersion != nil {
				t, err := db.ParseTime(g.ActiveVersion.SavedAt)
				if err != nil {
					return err
				}
				active = &syncrule.Active{ID: g.ActiveVersion.ID, SavedAt: t}
			}
			decision := syncrule.Decide(active, savedAt, req.base)

			if decision.Activate && active != nil {
				if _, err := tx.ExecContext(ctx, `UPDATE save_versions SET is_active = 0 WHERE id = ?`, active.ID); err != nil {
					return err
				}
			}
			var deviceID any
			if !p.isSession() {
				deviceID = p.DeviceID
			}
			ins, err := tx.ExecContext(ctx, `INSERT INTO save_versions (game_id, blob_hash, size, saved_at, saved_at_reported,
				uploaded_at, device_id, emulator, base_version_id, upload_id, is_active, conflict)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
				g.ID, hash, size, db.FormatTime(savedAt), reported, db.FormatTime(now), deviceID,
				req.emulator, req.base, req.uploadID, decision.Activate, decision.Conflict)
			if err != nil {
				return err
			}
			id, _ := ins.LastInsertId()
			v, _, err := s.loadVersion(ctx, tx, p.UserID, id)
			if err != nil {
				return err
			}
			res = uploadResult{Version: v, Created: true, Active: decision.Activate, Conflict: decision.Conflict}
			return nil
		})
	})
	if err != nil {
		return err
	}
	writeJSON(w, status, res)
	return nil
}

// profileParam returns the conversion profile of ?profile= (raw by default).
func profileParam(r *http.Request) (convert.Profile, error) {
	id := r.URL.Query().Get("profile")
	if id == "" {
		id = "raw"
	}
	p, ok := convert.Get(id)
	if !ok {
		return nil, errInvalid("unknown profile (expected one of " + strings.Join(convert.IDs(), ", ") + ")")
	}
	return p, nil
}

// decodeUpload converts the uploaded file to the canonical raw format.
func (s *Server) decodeUpload(r *http.Request, body []byte) ([]byte, error) {
	p, err := profileParam(r)
	if err != nil {
		return nil, err
	}
	data, err := p.Decode(body)
	if err != nil {
		return nil, errInvalid(err.Error())
	}
	return data, nil
}

// GET /versions/{id}/export?profile=desmume
func (s *Server) exportVersion(w http.ResponseWriter, r *http.Request) error {
	prof, err := profileParam(r)
	if err != nil {
		return err
	}
	v, _, err := s.versionParam(r)
	if err != nil {
		return err
	}
	raw, err := s.blobs.Read(v.SHA256)
	if err != nil {
		return err
	}
	out := prof.Encode(raw)
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, safeFilename(v.GameCode, prof.Extension())))
	w.Header().Set("Content-Length", strconv.Itoa(len(out)))
	w.Header().Set("X-Content-SHA256", blobs.Sum(out))
	w.WriteHeader(http.StatusOK)
	// A binary attachment served with nosniff, not HTML.
	_, _ = w.Write(out) //nolint:gosec // G705 false positive
	return nil
}

func (s *Server) loadOrCreateGame(ctx context.Context, tx *sql.Tx, userID int64, code, title string, now time.Time) (gameRow, error) {
	g, err := s.loadGame(ctx, tx, userID, code)
	if err == nil {
		return g, nil
	}
	var apiErr *Error
	if !errors.As(err, &apiErr) || apiErr.Code != "not_found" {
		return g, err
	}
	if title == "" {
		title = code
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO games (user_id, game_code, title, region, first_seen_at) VALUES (?, ?, ?, ?, ?)`,
		userID, code, title, gameRegion(code), db.FormatTime(now)); err != nil {
		return g, err
	}
	return s.loadGame(ctx, tx, userID, code)
}

// versionParam loads the {id} version of the caller's account.
func (s *Server) versionParam(r *http.Request) (versionJSON, int64, error) {
	id, err := pathID(r, "id")
	if err != nil {
		return versionJSON{}, 0, err
	}
	return s.loadVersion(r.Context(), s.db, principalFrom(r.Context()).UserID, id)
}

// safeFilename turns a game code into a file name.
func safeFilename(code, ext string) string {
	return strings.ReplaceAll(code, ":", "_") + ext
}

// GET /versions/{id}/content
func (s *Server) getContent(w http.ResponseWriter, r *http.Request) error {
	v, _, err := s.versionParam(r)
	if err != nil {
		return err
	}
	f, err := s.blobs.Open(v.SHA256)
	if err != nil {
		return err
	}
	defer f.Close()
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, safeFilename(v.GameCode, ".sav")))
	w.Header().Set("X-Content-SHA256", v.SHA256)
	w.Header().Set("ETag", `"`+v.SHA256+`"`)
	http.ServeContent(w, r, "", time.Time{}, f)
	return nil
}

// POST /versions/{id}/activate
func (s *Server) activateVersion(w http.ResponseWriter, r *http.Request) error {
	v, gameID, err := s.versionParam(r)
	if err != nil {
		return err
	}
	ctx := r.Context()
	err = s.inTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `UPDATE save_versions SET is_active = 0 WHERE game_id = ? AND is_active = 1`, gameID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `UPDATE save_versions SET is_active = 1 WHERE id = ?`, v.ID)
		return err
	})
	if err != nil {
		return err
	}
	v, _, err = s.loadVersion(ctx, s.db, principalFrom(ctx).UserID, v.ID)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"version": v})
	return nil
}

const maxNoteLen = 500

// PATCH /versions/{id}
func (s *Server) patchVersion(w http.ResponseWriter, r *http.Request) error {
	v, _, err := s.versionParam(r)
	if err != nil {
		return err
	}
	var req struct {
		Pinned *bool   `json:"pinned"`
		Note   *string `json:"note"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	ctx := r.Context()
	if req.Pinned != nil {
		if _, err := s.db.ExecContext(ctx, `UPDATE save_versions SET pinned = ? WHERE id = ?`, *req.Pinned, v.ID); err != nil {
			return err
		}
	}
	if req.Note != nil {
		note := strings.TrimSpace(*req.Note)
		if utf8.RuneCountInString(note) > maxNoteLen || !utf8.ValidString(note) {
			return errInvalid("the note must be at most 500 characters")
		}
		if _, err := s.db.ExecContext(ctx, `UPDATE save_versions SET note = ? WHERE id = ?`, note, v.ID); err != nil {
			return err
		}
	}
	v, _, err = s.loadVersion(ctx, s.db, principalFrom(ctx).UserID, v.ID)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"version": v})
	return nil
}
