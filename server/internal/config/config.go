// Package config loads the server configuration from environment variables.
package config

import (
	"fmt"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config holds every runtime setting of the server.
type Config struct {
	// Port is the TCP port the HTTP server listens on.
	Port int
	// DataDir holds the SQLite database and the blob store.
	DataDir string
	// MaxUpload is the maximum size of an uploaded save, in bytes.
	MaxUpload int64
	// TrustedProxies lists the networks whose X-Forwarded-For header is honoured.
	TrustedProxies []netip.Prefix
	// RetentionInterval is the period of the retention job.
	RetentionInterval time.Duration
	// Updates enables the update relay (ROMSYNC_UPDATES=off disables it).
	Updates bool
	// UpdateRepo is the GitHub repository whose releases are relayed.
	UpdateRepo string
	// GitHubToken is optional: only needed for a private repository.
	GitHubToken string
	// UpdateInterval is the period of the release check.
	UpdateInterval time.Duration
}

// Defaults returns the configuration used when no variable is set.
func Defaults() Config {
	return Config{
		Port:              8080,
		DataDir:           "/data",
		MaxUpload:         16 << 20,
		RetentionInterval: time.Hour,
		Updates:           true,
		UpdateRepo:        "dadoux01/romsync",
		UpdateInterval:    6 * time.Hour,
	}
}

// FromEnv reads the configuration from the process environment.
func FromEnv() (Config, error) {
	return Load(os.Getenv)
}

// Load reads the configuration through getenv, which makes it testable.
func Load(getenv func(string) string) (Config, error) {
	c := Defaults()

	if v := getenv("ROMSYNC_PORT"); v != "" {
		p, err := strconv.Atoi(v)
		if err != nil || p < 1 || p > 65535 {
			return c, fmt.Errorf("ROMSYNC_PORT: invalid port %q", v)
		}
		c.Port = p
	}
	if v := getenv("ROMSYNC_DATA_DIR"); v != "" {
		c.DataDir = v
	}
	if v := getenv("ROMSYNC_MAX_UPLOAD"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err != nil || n < 1 {
			return c, fmt.Errorf("ROMSYNC_MAX_UPLOAD: invalid size %q", v)
		}
		c.MaxUpload = n
	}
	if v := getenv("ROMSYNC_TRUSTED_PROXIES"); v != "" {
		prefixes, err := ParsePrefixes(v)
		if err != nil {
			return c, fmt.Errorf("ROMSYNC_TRUSTED_PROXIES: %w", err)
		}
		c.TrustedProxies = prefixes
	}
	if v := getenv("ROMSYNC_RETENTION_INTERVAL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d < time.Minute {
			return c, fmt.Errorf("ROMSYNC_RETENTION_INTERVAL: invalid duration %q (minimum 1m)", v)
		}
		c.RetentionInterval = d
	}
	switch strings.ToLower(getenv("ROMSYNC_UPDATES")) {
	case "", "on", "true", "1":
	case "off", "false", "0":
		c.Updates = false
	default:
		return c, fmt.Errorf("ROMSYNC_UPDATES: expected on or off, got %q", getenv("ROMSYNC_UPDATES"))
	}
	if v := strings.TrimSpace(getenv("ROMSYNC_UPDATE_REPO")); v != "" {
		owner, name, ok := strings.Cut(v, "/")
		if !ok || !validRepoPart(owner) || !validRepoPart(name) {
			return c, fmt.Errorf("ROMSYNC_UPDATE_REPO: expected owner/name, got %q", v)
		}
		c.UpdateRepo = v
	}
	c.GitHubToken = strings.TrimSpace(getenv("ROMSYNC_GITHUB_TOKEN"))
	if v := getenv("ROMSYNC_UPDATE_INTERVAL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d < 10*time.Minute {
			return c, fmt.Errorf("ROMSYNC_UPDATE_INTERVAL: invalid duration %q (minimum 10m)", v)
		}
		c.UpdateInterval = d
	}
	return c, nil
}

// validRepoPart accepts a GitHub owner or repository name.
func validRepoPart(s string) bool {
	if s == "" || s == "." || s == ".." {
		return false
	}
	for _, r := range s {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.') {
			return false
		}
	}
	return true
}

// ParsePrefixes parses a comma-separated list of IP addresses or CIDR networks.
func ParsePrefixes(list string) ([]netip.Prefix, error) {
	var out []netip.Prefix
	for _, item := range strings.Split(list, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if strings.Contains(item, "/") {
			p, err := netip.ParsePrefix(item)
			if err != nil {
				return nil, fmt.Errorf("invalid network %q", item)
			}
			out = append(out, p.Masked())
			continue
		}
		a, err := netip.ParseAddr(item)
		if err != nil {
			return nil, fmt.Errorf("invalid address %q", item)
		}
		a = a.Unmap()
		out = append(out, netip.PrefixFrom(a, a.BitLen()))
	}
	return out, nil
}
