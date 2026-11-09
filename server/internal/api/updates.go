package api

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/dadoux01/romsync/server/internal/updates"
)

// APILevel tells the clients which features this server has
// (docs/SPEC.md, "Compatibilité"). Servers before 0.5.0 have no
// GET /server and count as level 1.
//
//	2: X-Activate (choice after a divergence), chip_size on GET /active,
//	   DELETE /versions/{id}, update relay.
const APILevel = 2

// MinClientVersion is the oldest client this server works with.
const MinClientVersion = "0.4.0"

// GET /server
func (s *Server) getServer(w http.ResponseWriter, r *http.Request) error {
	writeJSON(w, http.StatusOK, map[string]any{
		"version":            s.version,
		"api_level":          APILevel,
		"min_client_version": MinClientVersion,
		"updates":            s.updates != nil,
	})
	return nil
}

func errUpdatesUnavailable(msg string) *Error {
	return newErr(http.StatusServiceUnavailable, "updates_unavailable", msg)
}

// UpdateMaxAge is how old the relay's knowledge of the latest release may
// be when a client asks: older, GitHub is checked again first.
const UpdateMaxAge = 10 * time.Minute

// latestRelease returns the relayed release, or an error for the client.
func (s *Server) latestRelease(ctx context.Context) (*updates.Release, time.Time, error) {
	if s.updates == nil {
		return nil, time.Time{}, errUpdatesUnavailable("the update relay is disabled on this server (ROMSYNC_UPDATES=off)")
	}
	// A slow GitHub must not hold the client long: the previous answer is
	// used when the check does not finish in time.
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	rel, at, err := s.updates.LatestFresh(ctx, UpdateMaxAge)
	if rel == nil {
		msg := "no release known yet"
		if err != nil {
			msg += ": " + err.Error()
		}
		return nil, at, errUpdatesUnavailable(msg)
	}
	return rel, at, nil
}

// GET /updates: the latest release, for the website's banner.
func (s *Server) getUpdates(w http.ResponseWriter, r *http.Request) error {
	rel, at, err := s.latestRelease(r.Context())
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"server_version": s.version,
		"latest": map[string]any{
			"version":      rel.Version,
			"notes":        rel.Notes,
			"published_at": rel.PublishedAt.UTC().Format(time.RFC3339),
			"url":          rel.HTMLURL,
		},
		"checked_at": at.UTC().Format(time.RFC3339),
	})
	return nil
}

func fileURL(version, name string) string {
	return "/api/v1/updates/files/" + version + "/" + name
}

// GET /updates/{platform}: the latest client of a platform and the signed
// checksums. The client compares the version and verifies the files.
func (s *Server) getPlatformUpdate(w http.ResponseWriter, r *http.Request) error {
	platform := chi.URLParam(r, "platform")
	if _, ok := updates.Platforms[platform]; !ok {
		return errNotFound("unknown platform")
	}
	rel, _, err := s.latestRelease(r.Context())
	if err != nil {
		return err
	}
	file, ok := rel.Find(updates.AssetName(rel.Version, platform))
	sums, ok2 := rel.Find(updates.SumsName)
	sig, ok3 := rel.Find(updates.SignatureName)
	if !ok || !ok2 || !ok3 {
		return errNotFound("the latest release has no signed file for this platform")
	}
	asset := func(a updates.Asset) map[string]any {
		return map[string]any{"name": a.Name, "size": a.Size, "url": fileURL(rel.Version, a.Name)}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"version":      rel.Version,
		"notes":        rel.Notes,
		"published_at": rel.PublishedAt.UTC().Format(time.RFC3339),
		"file":         asset(file),
		"sums":         asset(sums),
		"signature":    asset(sig),
	})
	return nil
}

// GET /updates/files/{version}/{name}: a file of the latest release, from
// the server's cache.
func (s *Server) getUpdateFile(w http.ResponseWriter, r *http.Request) error {
	if _, _, err := s.latestRelease(r.Context()); err != nil {
		return err
	}
	f, err := s.updates.Open(r.Context(), chi.URLParam(r, "version"), chi.URLParam(r, "name"))
	if errors.Is(err, updates.ErrNotFound) {
		return errNotFound(err.Error())
	}
	if err != nil {
		return newErr(http.StatusBadGateway, "updates_unavailable", "cannot get the file from GitHub: "+err.Error())
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return err
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", `attachment; filename="`+st.Name()+`"`)
	http.ServeContent(w, r, "", st.ModTime(), f)
	return nil
}
