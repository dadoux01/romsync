package config

import (
	"testing"
	"time"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadDefaults(t *testing.T) {
	c, err := Load(env(nil))
	if err != nil {
		t.Fatal(err)
	}
	if c.Port != 8080 || c.DataDir != "/data" || c.MaxUpload != 16<<20 || c.RetentionInterval != time.Hour {
		t.Fatalf("unexpected defaults: %+v", c)
	}
	if len(c.TrustedProxies) != 0 {
		t.Fatalf("trusted proxies must be empty by default")
	}
	if !c.Updates || c.UpdateRepo != "dadoux01/romsync" || c.GitHubToken != "" || c.UpdateInterval != time.Hour {
		t.Fatalf("unexpected update defaults: %+v", c)
	}
}

func TestLoadUpdateSettings(t *testing.T) {
	c, err := Load(env(map[string]string{
		"ROMSYNC_UPDATES":         "off",
		"ROMSYNC_UPDATE_REPO":     "someone/romsync-fork",
		"ROMSYNC_GITHUB_TOKEN":    " ghp_example ",
		"ROMSYNC_UPDATE_INTERVAL": "1h",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.Updates || c.UpdateRepo != "someone/romsync-fork" || c.GitHubToken != "ghp_example" || c.UpdateInterval != time.Hour {
		t.Fatalf("unexpected update settings: %+v", c)
	}
}

func TestLoadValues(t *testing.T) {
	c, err := Load(env(map[string]string{
		"ROMSYNC_PORT":               "9000",
		"ROMSYNC_DATA_DIR":           "/srv/romsync",
		"ROMSYNC_MAX_UPLOAD":         "1024",
		"ROMSYNC_TRUSTED_PROXIES":    "127.0.0.1, 100.64.0.0/10,::1",
		"ROMSYNC_RETENTION_INTERVAL": "30m",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.Port != 9000 || c.DataDir != "/srv/romsync" || c.MaxUpload != 1024 || c.RetentionInterval != 30*time.Minute {
		t.Fatalf("unexpected config: %+v", c)
	}
	if len(c.TrustedProxies) != 3 || c.TrustedProxies[0].String() != "127.0.0.1/32" || c.TrustedProxies[1].String() != "100.64.0.0/10" {
		t.Fatalf("unexpected proxies: %v", c.TrustedProxies)
	}
}

func TestLoadErrors(t *testing.T) {
	for _, tc := range []map[string]string{
		{"ROMSYNC_PORT": "0"},
		{"ROMSYNC_PORT": "abc"},
		{"ROMSYNC_MAX_UPLOAD": "-1"},
		{"ROMSYNC_TRUSTED_PROXIES": "not-an-ip"},
		{"ROMSYNC_RETENTION_INTERVAL": "10s"},
		{"ROMSYNC_UPDATES": "maybe"},
		{"ROMSYNC_UPDATE_REPO": "no-slash"},
		{"ROMSYNC_UPDATE_REPO": "a/b/c"},
		{"ROMSYNC_UPDATE_REPO": "../x"},
		{"ROMSYNC_UPDATE_INTERVAL": "1m"},
	} {
		if _, err := Load(env(tc)); err == nil {
			t.Errorf("expected an error for %v", tc)
		}
	}
}
