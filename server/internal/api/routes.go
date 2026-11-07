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
	r.Post("/pair", s.handle(s.postPair))

	// Web session or device token.
	r.Group(func(r chi.Router) {
		r.Use(s.require(authAny))
		r.Get("/me", s.handle(s.getMe))
		r.Get("/games", s.handle(s.listGames))
		r.Get("/games/{code}/active", s.handle(s.getActive))
		r.Get("/games/{code}/versions", s.handle(s.listVersions))
		r.Post("/games/{code}/versions", s.handle(s.postVersion))
		r.Get("/versions/{id}/content", s.handle(s.getContent))
	})

	// Web session only.
	r.Group(func(r chi.Router) {
		r.Use(s.require(authSession))
		r.Post("/auth/logout", s.handle(s.postLogout))
		r.Patch("/me", s.handle(s.patchMe))
		r.Post("/pair-codes", s.handle(s.postPairCode))
		r.Get("/devices", s.handle(s.listDevices))
		r.Delete("/devices/{id}", s.handle(s.deleteDevice))
		r.Patch("/games/{code}", s.handle(s.patchGame))
		r.Post("/versions/{id}/activate", s.handle(s.activateVersion))
		r.Patch("/versions/{id}", s.handle(s.patchVersion))
		r.Get("/versions/{id}/export", s.handle(s.exportVersion))
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
