package api

import (
	"errors"
	"log/slog"
	"net/http"
)

// Error is an API error, rendered as {"error": {"code": "...", "message": "..."}}.
type Error struct {
	Status  int
	Code    string
	Message string
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

func newErr(status int, code, msg string) *Error {
	return &Error{Status: status, Code: code, Message: msg}
}

// Error constructors, one per code of the specification.
func errInvalid(msg string) *Error { return newErr(http.StatusBadRequest, "invalid_request", msg) }
func errHashMismatch() *Error {
	return newErr(http.StatusBadRequest, "hash_mismatch", "content does not match X-Content-SHA256")
}
func errUnauthorized(msg string) *Error {
	return newErr(http.StatusUnauthorized, "unauthorized", msg)
}
func errForbidden(msg string) *Error { return newErr(http.StatusForbidden, "forbidden", msg) }
func errNotFound(msg string) *Error  { return newErr(http.StatusNotFound, "not_found", msg) }
func errAlreadySetup() *Error {
	return newErr(http.StatusConflict, "already_setup", "the server is already set up")
}
func errSizeMismatch(msg string) *Error { return newErr(http.StatusConflict, "size_mismatch", msg) }
func errConflict(msg string) *Error     { return newErr(http.StatusConflict, "conflict", msg) }
func errExpired(msg string) *Error      { return newErr(http.StatusGone, "expired", msg) }
func errTooLarge() *Error {
	return newErr(http.StatusRequestEntityTooLarge, "too_large", "the file exceeds the upload limit")
}
func errRateLimited() *Error {
	return newErr(http.StatusTooManyRequests, "rate_limited", "too many attempts, try again in a minute")
}

type errorBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// writeError renders err; anything that is not an *Error becomes a 500.
func writeError(w http.ResponseWriter, r *http.Request, err error) {
	var apiErr *Error
	if !errors.As(err, &apiErr) {
		slog.Error("internal error", "method", r.Method, "path", r.URL.Path, "err", err)
		apiErr = newErr(http.StatusInternalServerError, "internal", "internal server error")
	}
	var body errorBody
	body.Error.Code = apiErr.Code
	body.Error.Message = apiErr.Message
	if apiErr.Status == http.StatusTooManyRequests {
		w.Header().Set("Retry-After", "60")
	}
	writeJSON(w, apiErr.Status, body)
}
