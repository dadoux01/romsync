// Package updates relays the GitHub Releases of RomSync to the clients
// (docs/SPEC.md, "Mises à jour"): the server checks the latest release
// periodically and serves its files from a local cache, so that the apps
// (and the 3DS, which has no reliable HTTPS) only talk to their server.
// The files are signed: the clients verify them, the relay is not trusted.
package updates

import (
	"strconv"
	"strings"
)

// Version is a release version: MAJOR.MINOR.PATCH with an optional
// pre-release suffix ("0.5.0-rc1").
type Version struct {
	Major, Minor, Patch int
	Pre                 string
}

// ParseVersion parses "0.5.0", "v0.5.0" or "0.5.0-rc1".
func ParseVersion(s string) (Version, bool) {
	s = strings.TrimPrefix(strings.TrimSpace(s), "v")
	core, pre, _ := strings.Cut(s, "-")
	parts := strings.Split(core, ".")
	if len(parts) != 3 {
		return Version{}, false
	}
	var n [3]int
	for i, p := range parts {
		v, err := strconv.Atoi(p)
		if err != nil || v < 0 || p == "" || (len(p) > 1 && p[0] == '0') {
			return Version{}, false
		}
		n[i] = v
	}
	if strings.Contains(s, "-") && pre == "" {
		return Version{}, false
	}
	return Version{Major: n[0], Minor: n[1], Patch: n[2], Pre: pre}, true
}

// Compare returns -1, 0 or 1. A pre-release is older than its release
// (0.5.0-rc1 < 0.5.0); pre-release suffixes compare as strings.
func (v Version) Compare(o Version) int {
	for _, d := range [][2]int{{v.Major, o.Major}, {v.Minor, o.Minor}, {v.Patch, o.Patch}} {
		if d[0] != d[1] {
			if d[0] < d[1] {
				return -1
			}
			return 1
		}
	}
	switch {
	case v.Pre == o.Pre:
		return 0
	case v.Pre == "":
		return 1
	case o.Pre == "":
		return -1
	case v.Pre < o.Pre:
		return -1
	default:
		return 1
	}
}

func (v Version) String() string {
	s := strconv.Itoa(v.Major) + "." + strconv.Itoa(v.Minor) + "." + strconv.Itoa(v.Patch)
	if v.Pre != "" {
		s += "-" + v.Pre
	}
	return s
}
