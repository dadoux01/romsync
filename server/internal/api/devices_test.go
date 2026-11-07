package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

type pairRequest struct {
	Code     string `json:"code"`
	Name     string `json:"name"`
	Platform string `json:"platform"`
}

// pairDevice pairs a new device for the logged-in user and returns a client
// authenticated with its token.
func (e *testEnv) pairDevice(user *client, name string) (*client, deviceJSON) {
	e.t.Helper()
	var pc struct{ Code string }
	r := user.post("/api/v1/pair-codes", nil)
	expect(e.t, r, http.StatusCreated)
	r.json(e.t, &pc)
	var res struct {
		Token  string
		Device deviceJSON
	}
	r = e.client().post("/api/v1/pair", pairRequest{Code: pc.Code, Name: name, Platform: "linux"})
	expect(e.t, r, http.StatusCreated)
	r.json(e.t, &res)
	dev := e.client()
	dev.token = res.Token
	return dev, res.Device
}

func TestPairingFlow(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()

	var pc struct {
		Code      string
		ExpiresAt string `json:"expires_at"`
	}
	r := admin.post("/api/v1/pair-codes", nil)
	expect(t, r, 201)
	r.json(t, &pc)
	if len(pc.Code) != 9 || pc.Code[4] != '-' {
		t.Fatalf("unexpected code %q", pc.Code)
	}

	anon := e.client()
	expectErr(t, anon.post("/api/v1/pair", pairRequest{Code: pc.Code, Name: "", Platform: "linux"}), 400, "invalid_request")
	expectErr(t, anon.post("/api/v1/pair", pairRequest{Code: pc.Code, Name: "PC", Platform: "amiga"}), 400, "invalid_request")

	// The code is accepted in lower case and without its dash.
	var res struct {
		Token  string
		Device deviceJSON
	}
	r = anon.post("/api/v1/pair", pairRequest{Code: strings.ToLower(strings.ReplaceAll(pc.Code, "-", "")), Name: "Fedora bureau", Platform: "linux"})
	expect(t, r, 201)
	r.json(t, &res)
	if len(res.Token) != 43 || res.Device.Name != "Fedora bureau" {
		t.Fatalf("unexpected pairing result %+v", res)
	}

	// Single use.
	expectErr(t, e.client().post("/api/v1/pair", pairRequest{Code: pc.Code, Name: "Other", Platform: "3ds"}), 410, "expired")

	// The token authenticates the device.
	dev := e.client()
	dev.token = res.Token
	var me struct {
		User   userJSON
		Device *deviceJSON
	}
	r = dev.get("/api/v1/me")
	expect(t, r, 200)
	r.json(t, &me)
	if me.User.Username != "admin" || me.Device == nil || me.Device.ID != res.Device.ID {
		t.Fatalf("unexpected /me for a device: %+v", me)
	}

	// Devices cannot use session-only routes.
	expectErr(t, dev.get("/api/v1/devices"), 403, "forbidden")
	expectErr(t, dev.post("/api/v1/pair-codes", nil), 403, "forbidden")

	var list struct{ Devices []deviceJSON }
	admin.get("/api/v1/devices").json(t, &list)
	if len(list.Devices) != 1 || list.Devices[0].LastSeenAt == nil {
		t.Fatalf("unexpected devices %+v", list.Devices)
	}

	// Revocation.
	expect(t, admin.delete(fmt.Sprintf("/api/v1/devices/%d", res.Device.ID)), 204)
	expectErr(t, dev.get("/api/v1/me"), 401, "unauthorized")
	admin.get("/api/v1/devices").json(t, &list)
	if list.Devices[0].RevokedAt == nil {
		t.Fatal("device must be marked revoked")
	}
}

func TestPairCodeExpiresAfter10Minutes(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	var pc struct{ Code string }
	admin.post("/api/v1/pair-codes", nil).json(t, &pc)
	e.clock.Advance(10*time.Minute + time.Second)
	expectErr(t, e.client().post("/api/v1/pair", pairRequest{Code: pc.Code, Name: "PC", Platform: "linux"}), 410, "expired")
}

func TestPairRateLimitAndUnknownCode(t *testing.T) {
	e := newTestEnv(t)
	e.setupAdmin()
	c := e.client()
	for i := 0; i < 5; i++ {
		expectErr(t, c.post("/api/v1/pair", pairRequest{Code: "AAAA-AAAA", Name: "PC", Platform: "linux"}), 404, "not_found")
	}
	expectErr(t, c.post("/api/v1/pair", pairRequest{Code: "AAAA-AAAA", Name: "PC", Platform: "linux"}), 429, "rate_limited")
}

func TestDevicesAreScopedToTheirAccount(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	alice := e.newUser(admin, "alice")
	_, dev := e.pairDevice(admin, "Admin PC")

	expectErr(t, alice.delete(fmt.Sprintf("/api/v1/devices/%d", dev.ID)), 404, "not_found")
	var list struct{ Devices []deviceJSON }
	alice.get("/api/v1/devices").json(t, &list)
	if len(list.Devices) != 0 {
		t.Fatal("alice must not see admin's devices")
	}
}

func TestDisabledAccountBlocksDevices(t *testing.T) {
	e := newTestEnv(t)
	admin := e.setupAdmin()
	alice := e.newUser(admin, "alice")
	dev, _ := e.pairDevice(alice, "Alice PC")
	expect(t, dev.get("/api/v1/me"), 200)

	var me struct{ User userJSON }
	alice.get("/api/v1/me").json(t, &me)
	expect(t, admin.patch(fmt.Sprintf("/api/v1/users/%d", me.User.ID), map[string]bool{"disabled": true}), 200)
	expectErr(t, dev.get("/api/v1/me"), 401, "unauthorized")
}
