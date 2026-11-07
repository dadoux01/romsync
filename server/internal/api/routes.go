package api

import "github.com/go-chi/chi/v5"

// routes declares every API route. Keep it in sync with api/openapi.yaml:
// TestOpenAPICoversRoutes fails when a route is missing from the spec.
func (s *Server) routes(r chi.Router) {
}
