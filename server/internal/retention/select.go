package retention

import (
	"fmt"
	"sort"
	"time"
)

// Bands of the smart policy.
const (
	smartKeepAll = 7 * 24 * time.Hour
	smartDaily   = 30 * 24 * time.Hour
)

// Version is what the selection needs to know about a save version.
type Version struct {
	ID      int64
	SavedAt time.Time
	Active  bool
	Pinned  bool
}

// Select returns the ids of the versions that policy removes at now.
//
// The kept set is the one the mode designates, to which the active version
// and pinned versions are always added: they are never removed.
func Select(versions []Version, p Policy, now time.Time) []int64 {
	sorted := make([]Version, len(versions))
	copy(sorted, versions)
	// Newest first, so the first version met in a bucket is its most recent.
	sort.Slice(sorted, func(i, j int) bool {
		if !sorted[i].SavedAt.Equal(sorted[j].SavedAt) {
			return sorted[i].SavedAt.After(sorted[j].SavedAt)
		}
		return sorted[i].ID > sorted[j].ID
	})

	keep := make(map[int64]bool, len(sorted))
	switch p.Mode {
	case ModeAll:
		return nil
	case ModeLastN:
		for i, v := range sorted {
			if i < p.N {
				keep[v.ID] = true
			}
		}
	case ModeDays:
		limit := time.Duration(p.N) * 24 * time.Hour
		for _, v := range sorted {
			if now.Sub(v.SavedAt) < limit {
				keep[v.ID] = true
			}
		}
	case ModeSmart:
		seen := map[string]bool{}
		for _, v := range sorted {
			age := now.Sub(v.SavedAt)
			var bucket string
			switch {
			case age < smartKeepAll:
				keep[v.ID] = true
				continue
			case age < smartDaily:
				bucket = "d" + v.SavedAt.UTC().Format("2006-01-02")
			default:
				y, w := v.SavedAt.UTC().ISOWeek()
				bucket = fmt.Sprintf("w%d-%02d", y, w)
			}
			if !seen[bucket] {
				seen[bucket] = true
				keep[v.ID] = true
			}
		}
	default:
		// Unknown policies never delete anything.
		return nil
	}

	var remove []int64
	for _, v := range sorted {
		if !keep[v.ID] && !v.Active && !v.Pinned {
			remove = append(remove, v.ID)
		}
	}
	return remove
}
