package api

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"github.com/dadoux01/romsync/server/internal/retention"
)

// Accepted game identifiers (see docs/SPEC.md, "Identification des jeux").
var (
	cartridgeCodeRE = regexp.MustCompile(`^[A-Z0-9]{4}$`)
	romHashCodeRE   = regexp.MustCompile(`^h:[0-9a-f]{40}$`)
	customCodeRE    = regexp.MustCompile(`^x:[a-z0-9-]{1,32}$`)
)

func validGameCode(code string) bool {
	return cartridgeCodeRE.MatchString(code) || romHashCodeRE.MatchString(code) || customCodeRE.MatchString(code)
}

// gameRegion returns the region letter of a cartridge code, or nil.
func gameRegion(code string) *string {
	if !cartridgeCodeRE.MatchString(code) {
		return nil
	}
	r := code[3:]
	return &r
}

// gameCodeParam returns the decoded and validated {code} path parameter.
func gameCodeParam(r *http.Request) (string, error) {
	code, err := url.PathUnescape(chi.URLParam(r, "code"))
	if err != nil || !validGameCode(code) {
		return "", errInvalid("invalid game identifier (expected ABCD, h:<sha1> or x:<name>)")
	}
	return code, nil
}

const maxTitleLen = 128

func validTitle(t string) (string, error) {
	t = strings.TrimSpace(t)
	if t == "" || utf8.RuneCountInString(t) > maxTitleLen || !utf8.ValidString(t) {
		return "", errInvalid("the title must be 1 to 128 characters")
	}
	return t, nil
}

// gameJSON is the public representation of a game.
type gameJSON struct {
	Code            string            `json:"code"`
	Title           string            `json:"title"`
	Region          *string           `json:"region"`
	ChipSize        *int64            `json:"chip_size"`
	FirstSeenAt     string            `json:"first_seen_at"`
	RetentionPolicy *retention.Policy `json:"retention_policy"`
	VersionCount    int               `json:"version_count"`
	// Conflict is true when the most recently uploaded version diverged.
	Conflict      bool         `json:"conflict"`
	ActiveVersion *versionJSON `json:"active_version"`
}

type gameRow struct {
	ID int64
	gameJSON
}

const gameSelect = `SELECT g.id, g.game_code, g.title, g.region, g.chip_size, g.first_seen_at, g.retention_policy,
	(SELECT COUNT(*) FROM save_versions v WHERE v.game_id = g.id),
	COALESCE((SELECT v.conflict FROM save_versions v WHERE v.game_id = g.id ORDER BY v.uploaded_at DESC, v.id DESC LIMIT 1), 0)
	FROM games g`

func scanGame(row interface{ Scan(...any) error }) (gameRow, error) {
	var g gameRow
	var policy *string
	if err := row.Scan(&g.ID, &g.Code, &g.Title, &g.Region, &g.ChipSize, &g.FirstSeenAt, &policy,
		&g.VersionCount, &g.Conflict); err != nil {
		return g, err
	}
	if policy != nil {
		p, err := retention.Parse(*policy)
		if err != nil {
			return g, err
		}
		g.RetentionPolicy = &p
	}
	return g, nil
}

func (s *Server) loadGame(ctx context.Context, q execer, userID int64, code string) (gameRow, error) {
	g, err := scanGame(q.QueryRowContext(ctx, gameSelect+` WHERE g.user_id = ? AND g.game_code = ?`, userID, code))
	if errors.Is(err, sql.ErrNoRows) {
		return g, errNotFound("unknown game")
	}
	if err != nil {
		return g, err
	}
	g.ActiveVersion, err = s.activeVersion(ctx, q, g.ID)
	return g, err
}

// queryGames lists the user's games. The rows are closed before returning:
// the single database connection is needed for the next queries.
func (s *Server) queryGames(ctx context.Context, userID int64) ([]gameRow, error) {
	rows, err := s.db.QueryContext(ctx, gameSelect+` WHERE g.user_id = ? ORDER BY g.title COLLATE NOCASE, g.game_code`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var games []gameRow
	for rows.Next() {
		g, err := scanGame(rows)
		if err != nil {
			return nil, err
		}
		games = append(games, g)
	}
	return games, rows.Err()
}

// GET /games
func (s *Server) listGames(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	p := principalFrom(ctx)
	games, err := s.queryGames(ctx, p.UserID)
	if err != nil {
		return err
	}
	out := make([]gameJSON, 0, len(games))
	for _, g := range games {
		if g.ActiveVersion, err = s.activeVersion(ctx, s.db, g.ID); err != nil {
			return err
		}
		out = append(out, g.gameJSON)
	}
	writeJSON(w, http.StatusOK, map[string]any{"games": out})
	return nil
}

// PATCH /games/{code}
func (s *Server) patchGame(w http.ResponseWriter, r *http.Request) error {
	code, err := gameCodeParam(r)
	if err != nil {
		return err
	}
	var req struct {
		Title *string `json:"title"`
		// Raw so that an explicit null (inherit the account policy) can be
		// told apart from an absent field.
		RetentionPolicy json.RawMessage `json:"retention_policy"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	ctx := r.Context()
	p := principalFrom(ctx)
	g, err := s.loadGame(ctx, s.db, p.UserID, code)
	if err != nil {
		return err
	}
	if req.Title != nil {
		t, err := validTitle(*req.Title)
		if err != nil {
			return err
		}
		if _, err := s.db.ExecContext(ctx, `UPDATE games SET title = ? WHERE id = ?`, t, g.ID); err != nil {
			return err
		}
	}
	if len(req.RetentionPolicy) > 0 {
		var stored any // nil means inherit
		if !bytes.Equal(bytes.TrimSpace(req.RetentionPolicy), []byte("null")) {
			var pol retention.Policy
			if err := json.Unmarshal(req.RetentionPolicy, &pol); err != nil {
				return errInvalid("invalid retention_policy")
			}
			if err := pol.Validate(); err != nil {
				return errInvalid(err.Error())
			}
			stored = pol.Encode()
		}
		if _, err := s.db.ExecContext(ctx, `UPDATE games SET retention_policy = ? WHERE id = ?`, stored, g.ID); err != nil {
			return err
		}
	}
	g, err = s.loadGame(ctx, s.db, p.UserID, code)
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{"game": g.gameJSON})
	return nil
}
