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
}

// Defaults returns the configuration used when no variable is set.
func Defaults() Config {
	return Config{
		Port:              8080,
		DataDir:           "/data",
		MaxUpload:         16 << 20,
		RetentionInterval: time.Hour,
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
	return c, nil
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
