package api

import (
	"bufio"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

// openAPIOperations extracts "METHOD /path" pairs from api/openapi.yaml.
// It relies on the file's layout (paths at two spaces of indentation,
// methods at four) to avoid a YAML dependency; the file itself is validated
// by a linter in CI.
func openAPIOperations(t *testing.T) map[string]bool {
	t.Helper()
	f, err := os.Open(filepath.Join("..", "..", "..", "api", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	ops := map[string]bool{}
	inPaths := false
	path := ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case line == "paths:":
			inPaths = true
		case inPaths && len(line) > 0 && line[0] != ' ':
			inPaths = false
		case inPaths && strings.HasPrefix(line, "  /"):
			path = strings.TrimSuffix(strings.TrimSpace(line), ":")
		case inPaths && path != "" && strings.HasPrefix(line, "    ") && !strings.HasPrefix(line, "     "):
			m := strings.TrimSuffix(strings.TrimSpace(line), ":")
			switch m {
			case "get", "post", "put", "patch", "delete":
				ops[strings.ToUpper(m)+" "+path] = true
			}
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	return ops
}

// TestOpenAPICoversRoutes checks that the router and api/openapi.yaml
// declare exactly the same operations.
func TestOpenAPICoversRoutes(t *testing.T) {
	spec := openAPIOperations(t)
	if len(spec) == 0 {
		t.Fatal("no operation found in openapi.yaml")
	}
	r := chi.NewRouter()
	(&Server{}).routes(r)
	routes := map[string]bool{}
	err := chi.Walk(r, func(method, route string, _ http.Handler, _ ...func(http.Handler) http.Handler) error {
		routes[method+" "+strings.TrimSuffix(route, "/")] = true
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	var missing, extra []string
	for op := range routes {
		if !spec[op] {
			missing = append(missing, op)
		}
	}
	for op := range spec {
		if !routes[op] {
			extra = append(extra, op)
		}
	}
	sort.Strings(missing)
	sort.Strings(extra)
	if len(missing) > 0 {
		t.Errorf("routes missing from openapi.yaml: %v", missing)
	}
	if len(extra) > 0 {
		t.Errorf("operations in openapi.yaml without a route: %v", extra)
	}
}
