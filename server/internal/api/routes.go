package api

import "github.com/go-chi/chi/v5"

// routes declares every API route. Keep it in sync with api/openapi.yaml:
// TestOpenAPICoversRoutes fails when a route is missing from the spec.
func (s *Server) routes(r chi.Router) {
	// Anonymous routes.
	r.Get("/setup", s.handle(s.getSetup))
	r.Post("/setup", s.handle(s.postSetup))
	r.Post("/auth/login", s.handle(s.postLogin))
	r.Post("/invites/{token}/accept", s.handle(s.acceptInvite))

	// Web session or device token.
	r.Group(func(r chi.Router) {
		r.Use(s.require(authAny))
		r.Get("/me", s.handle(s.getMe))
	})

	// Web session only.
	r.Group(func(r chi.Router) {
		r.Use(s.require(authSession))
		r.Post("/auth/logout", s.handle(s.postLogout))
		r.Patch("/me", s.handle(s.patchMe))
	})

	// Administrator only.
	r.Group(func(r chi.Router) {
		r.Use(s.require(authAdmin))
		r.Get("/users", s.handle(s.listUsers))
		r.Patch("/users/{id}", s.handle(s.patchUser))
		r.Get("/invites", s.handle(s.listInvites))
		r.Post("/invites", s.handle(s.postInvite))
	})
}
