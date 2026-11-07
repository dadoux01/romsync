package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
)

// maxJSONBody bounds every JSON request body.
const maxJSONBody = 64 << 10

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v != nil {
		_ = json.NewEncoder(w).Encode(v)
	}
}

// decodeJSON decodes a JSON body into dst, rejecting unknown fields.
func decodeJSON(r *http.Request, dst any) error {
	if ct := r.Header.Get("Content-Type"); ct != "" && !strings.HasPrefix(ct, "application/json") {
		return errInvalid("expected an application/json body")
	}
	dec := json.NewDecoder(io.LimitReader(r.Body, maxJSONBody))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		if errors.Is(err, io.EOF) {
			return errInvalid("empty request body")
		}
		return errInvalid("invalid JSON body: " + err.Error())
	}
	if dec.More() {
		return errInvalid("unexpected data after the JSON body")
	}
	return nil
}

// handlerFunc is an http handler that returns an error instead of writing it.
type handlerFunc func(w http.ResponseWriter, r *http.Request) error

func (s *Server) handle(h handlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			writeError(w, r, err)
		}
	}
}
