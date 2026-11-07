// Package retention implements the save retention policies (all, last_n,
// days, smart) and the periodic job that applies them.
package retention

import (
	"encoding/json"
	"fmt"
)

// Retention modes.
const (
	ModeAll   = "all"
	ModeLastN = "last_n"
	ModeDays  = "days"
	ModeSmart = "smart"
)

// maxN bounds the N parameter to keep values sane.
const maxN = 100000

// Policy is a retention policy, stored as JSON.
type Policy struct {
	Mode string `json:"mode"`
	N    int    `json:"n,omitempty"`
}

// Default is the policy of a new account.
var Default = Policy{Mode: ModeSmart}

// Validate checks the mode and its parameter.
func (p Policy) Validate() error {
	switch p.Mode {
	case ModeAll, ModeSmart:
		if p.N != 0 {
			return fmt.Errorf("mode %q takes no n", p.Mode)
		}
	case ModeLastN, ModeDays:
		if p.N < 1 || p.N > maxN {
			return fmt.Errorf("mode %q requires 1 <= n <= %d", p.Mode, maxN)
		}
	default:
		return fmt.Errorf("unknown retention mode %q", p.Mode)
	}
	return nil
}

// Encode returns the JSON form stored in the database.
func (p Policy) Encode() string {
	b, _ := json.Marshal(p)
	return string(b)
}

// Parse decodes and validates a stored policy.
func Parse(s string) (Policy, error) {
	var p Policy
	if err := json.Unmarshal([]byte(s), &p); err != nil {
		return p, fmt.Errorf("invalid retention policy: %w", err)
	}
	return p, p.Validate()
}
