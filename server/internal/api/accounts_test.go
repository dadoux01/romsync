package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

const adminPassword = "admin-password"

// setupAdmin runs the first-start setup and returns the logged-in admin.
func (e *testEnv) setupAdmin() *client {
	e.t.Helper()
	c := e.client()
	r := c.post("/api/v1/setup", credentials{Username: "admin", Password: adminPassword})
	expect(e.t, r, http.StatusCreated)
	return c
}

// invite creates an invitation with admin and accepts it as username.
func (e *testEnv) newUser(admin *client, username string) *client {
	e.t.Helper()
	var inv struct {
		Token string `json:"token"`
	}
	r := admin.post("/api/v1/invites", nil)
	expect(e.t, r, http.StatusCreated)
	r.json(e.t, &inv)
	c := e.client()
	expect(e.t, c.post("/api/v1/invites/"+inv.Token+"/accept", credentials{Username: username, Password: "user-password"}), http.StatusCreated)
	return c
}

func TestSetupFlow(t *testing.T) {
	e := newTestEnv(t)
	anon := e.client()

	var st struct{ Needed bool }
	anon.get("/api/v1/setup").json(t, &st)
	if !st.Needed {
		t.Fatal("setup must be needed on an empty server")
	}

	expectErr(t, anon.post("/api/v1/setup", credentials{Username: "admin", Password: "short"}), 400, "invalid_request")
	expectErr(t, anon.post("/api/v1/setup", credentials{Username: "bad name!", Password: adminPassword}), 400, "invalid_request")

	admin := e.setupAdmin()
	var me struct {
		User   userJSON
		Device *deviceJSON
	}
	r := admin.get("/api/v1/me")
	expect(t, r, 200)
	r.json(t, &me)
	if me.User.Username != "admin" || me.User.Role != "admin" || me.Device != nil || me.User.RetentionPolicy.Mode != "smart" {
		t.Fatalf("unexpected /me: %+v", me)
	}

	anon.get("/api/v1/setup").json(t, &st)
	if st.Needed {
		t.Fatal("setup must no longer be needed")
	}
	expectErr(t, e.client().post("/api/v1/setup", credentials{Username: "other", Password: adminPassword}), 409, "already_setup")
}

func TestLoginLogout(t *testing.T) {
	e := newTestEnv(t)
	e.setupAdmin()

	c := e.client()
	expectErr(t, c.get("/api/v1/me"), 401, "unauthorized")
	expectErr(t, c.post("/api/v1/auth/login", credentials{Username: "admin", Password: "wrong-password"}), 401, "unauthorized")
	expectErr(t, c.post("/api/v1/auth/login", credentials{Username: "nobody", Password: "wrong-password"}), 401, "unauthorized")

	r := c.post("/api/v1/auth/login", credentials{Username: "ADMIN", Password: adminPassword})
	expect(t, r, 200)
	cookie := r.header.Get("Set-Cookie")
	for _, attr := range []string{"romsync_session=", "HttpOnly", "SameSite=Strict"} {
		if !strings.Contains(cookie, attr) {
			t.Fatalf("cookie %q lacks %s", cookie, attr)
		}
	}
	expect(t, c.get("/api/v1/me"), 200)
	expect(t, c.post("/api/v1/auth/logout", nil), 204)
	expectErr(t, c.get("/api/v1/me"), 401, "unauthorized")
}

func TestSessionExpiresAfter30DaysOfInactivity(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()

	e.clock.Advance(20 * 24 * time.Hour)
	expect(t, admin.get("/api/v1/me"), 200) // slides the expiration
	e.clock.Advance(20 * 24 * time.Hour)
	expect(t, admin.get("/api/v1/me"), 200)
	e.clock.Advance(31 * 24 * time.Hour)
	expectErr(t, admin.get("/api/v1/me"), 401, "unauthorized")
}

func TestLoginRateLimit(t *testing.T) {
	e := newTestEnv(t)
	e.setupAdmin()
	c := e.client()
	for i := 0; i < 5; i++ {
		expectErr(t, c.post("/api/v1/auth/login", credentials{Username: "admin", Password: "wrong-password"}), 401, "unauthorized")
	}
	r := c.post("/api/v1/auth/login", credentials{Username: "admin", Password: adminPassword})
	expectErr(t, r, 429, "rate_limited")
	if r.header.Get("Retry-After") == "" {
		t.Fatal("429 must carry Retry-After")
	}
	e.clock.Advance(61 * time.Second)
	expect(t, c.post("/api/v1/auth/login", credentials{Username: "admin", Password: adminPassword}), 200)
}

func TestInvites(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()

	var inv struct {
		Invite inviteJSON
		Token  string
	}
	r := admin.post("/api/v1/invites", map[string]int{"expires_in_days": 1})
	expect(t, r, 201)
	r.json(t, &inv)
	if inv.Token == "" || inv.Invite.Status != "pending" {
		t.Fatalf("unexpected invite: %+v", inv)
	}

	alice := e.client()
	expectErr(t, alice.post("/api/v1/invites/not-a-token/accept", credentials{Username: "alice", Password: "alice-password"}), 404, "not_found")
	expectErr(t, alice.post("/api/v1/invites/"+inv.Token+"/accept", credentials{Username: "admin", Password: "alice-password"}), 409, "conflict")
	r = alice.post("/api/v1/invites/"+inv.Token+"/accept", credentials{Username: "alice", Password: "alice-password"})
	expect(t, r, 201)

	// Accepting signs the new user in.
	var me struct{ User userJSON }
	alice.get("/api/v1/me").json(t, &me)
	if me.User.Username != "alice" || me.User.Role != "user" {
		t.Fatalf("unexpected user %+v", me.User)
	}

	// Single use.
	expectErr(t, e.client().post("/api/v1/invites/"+inv.Token+"/accept", credentials{Username: "bob", Password: "bob-password"}), 410, "expired")

	// Expiration.
	admin.post("/api/v1/invites", nil).json(t, &inv)
	e.clock.Advance(7*24*time.Hour + time.Second)
	expectErr(t, e.client().post("/api/v1/invites/"+inv.Token+"/accept", credentials{Username: "bob", Password: "bob-password"}), 410, "expired")

	var list struct{ Invites []inviteJSON }
	admin.get("/api/v1/invites").json(t, &list)
	if len(list.Invites) != 2 || list.Invites[0].Status != "expired" || list.Invites[1].Status != "used" ||
		list.Invites[1].UsedByName == nil || *list.Invites[1].UsedByName != "alice" {
		t.Fatalf("unexpected invite list: %+v", list.Invites)
	}

	// Regular users cannot manage invitations or users.
	expectErr(t, alice.post("/api/v1/invites", nil), 403, "forbidden")
	expectErr(t, alice.get("/api/v1/invites"), 403, "forbidden")
	expectErr(t, alice.get("/api/v1/users"), 403, "forbidden")
}

func TestAdminDisablesAndResetsUsers(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	alice := e.newUser(admin, "alice")

	var me struct{ User userJSON }
	alice.get("/api/v1/me").json(t, &me)
	aliceURL := fmt.Sprintf("/api/v1/users/%d", me.User.ID)

	var users struct{ Users []userJSON }
	admin.get("/api/v1/users").json(t, &users)
	if len(users.Users) != 2 {
		t.Fatalf("expected 2 users, got %d", len(users.Users))
	}

	expectErr(t, admin.patch("/api/v1/users/1", map[string]bool{"disabled": true}), 403, "forbidden")
	expectErr(t, admin.patch("/api/v1/users/999", map[string]bool{"disabled": true}), 404, "not_found")

	expect(t, admin.patch(aliceURL, map[string]bool{"disabled": true}), 200)
	expectErr(t, alice.get("/api/v1/me"), 401, "unauthorized")
	expectErr(t, e.client().post("/api/v1/auth/login", credentials{Username: "alice", Password: "user-password"}), 401, "unauthorized")

	expect(t, admin.patch(aliceURL, map[string]any{"disabled": false, "password": "new-password"}), 200)
	expectErr(t, e.client().post("/api/v1/auth/login", credentials{Username: "alice", Password: "user-password"}), 401, "unauthorized")
	expect(t, e.client().post("/api/v1/auth/login", credentials{Username: "alice", Password: "new-password"}), 200)
}

func TestPatchMe(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	other := e.client()
	expect(t, other.post("/api/v1/auth/login", credentials{Username: "admin", Password: adminPassword}), 200)

	expectErr(t, admin.patch("/api/v1/me", map[string]any{"retention_policy": map[string]any{"mode": "last_n"}}), 400, "invalid_request")
	expectErr(t, admin.patch("/api/v1/me", map[string]any{"retention_policy": map[string]any{"mode": "forever"}}), 400, "invalid_request")

	var me struct{ User userJSON }
	r := admin.patch("/api/v1/me", map[string]any{"retention_policy": map[string]any{"mode": "last_n", "n": 5}})
	expect(t, r, 200)
	r.json(t, &me)
	if me.User.RetentionPolicy.Mode != "last_n" || me.User.RetentionPolicy.N != 5 {
		t.Fatalf("policy not updated: %+v", me.User.RetentionPolicy)
	}

	expectErr(t, admin.patch("/api/v1/me", map[string]any{"new_password": "another-password"}), 400, "invalid_request")
	expectErr(t, admin.patch("/api/v1/me", map[string]any{"current_password": "nope", "new_password": "another-password"}), 403, "forbidden")
	expect(t, admin.patch("/api/v1/me", map[string]any{"current_password": adminPassword, "new_password": "another-password"}), 200)

	// The current session survives, the other one is closed.
	expect(t, admin.get("/api/v1/me"), 200)
	expectErr(t, other.get("/api/v1/me"), 401, "unauthorized")
}

func TestJSONBodyValidation(t *testing.T) {
	e := newTestEnv(t)
	c := e.client()
	expectErr(t, c.do("POST", "/api/v1/setup", strings.NewReader(`{"username":"a","password":"12345678","extra":1}`),
		map[string]string{"Content-Type": "application/json"}), 400, "invalid_request")
	expectErr(t, c.do("POST", "/api/v1/setup", strings.NewReader(`not json`),
		map[string]string{"Content-Type": "application/json"}), 400, "invalid_request")
}
