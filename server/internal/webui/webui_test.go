package webui

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
)

func TestHandlerServesFilesAndFallsBackToIndex(t *testing.T) {
	h := handler(fstest.MapFS{
		"index.html":    {Data: []byte("<html>app</html>")},
		"assets/app.js": {Data: []byte("console.log(1)")},
	})

	for _, tc := range []struct{ path, want string }{
		{"/", "<html>app</html>"},
		{"/games/IRBF", "<html>app</html>"},
		{"/assets/app.js", "console.log(1)"},
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, tc.path, nil))
		if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), tc.want) {
			t.Errorf("%s: got %d %q", tc.path, rec.Code, rec.Body.String())
		}
	}
}

func TestHandlerPlaceholderWithoutBuild(t *testing.T) {
	rec := httptest.NewRecorder()
	handler(fstest.MapFS{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "not built") {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
}
