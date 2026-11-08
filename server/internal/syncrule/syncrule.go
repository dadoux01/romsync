// Package syncrule implements the "most recent wins" rule of the sync
// protocol and the correction of clocks set in the future.
package syncrule

import "time"

// MaxClockSkew is the tolerated gap between a reported saved_at in the
// future and the time the server received the save.
const MaxClockSkew = 5 * time.Minute

// Precision is the precision of stored dates; comparisons happen at it.
const Precision = time.Millisecond

// Active describes the current active version of a game.
type Active struct {
	ID      int64
	SavedAt time.Time
}

// Decision is the outcome of an upload.
type Decision struct {
	// Activate tells whether the new version becomes the active one.
	Activate bool
	// Conflict tells whether the upload diverged from the active version.
	Conflict bool
}

// Activation is the client's choice about activating an upload (the
// X-Activate header).
type Activation int

const (
	// ActivateAuto applies "most recent wins" (no header).
	ActivateAuto Activation = iota
	// ActivateAlways makes the upload active whatever its date: the user
	// chose the local save after a divergence.
	ActivateAlways
	// ActivateNever keeps the upload as an inactive version: the user chose
	// the server's save and the local one is only archived.
	ActivateNever
)

// Decide applies the rule to an upload made at savedAt from baseVersionID
// (nil when the client had no version).
//
//   - The first save of a game always becomes active, whatever activation.
//   - With ActivateAlways or ActivateNever, the client's choice applies.
//   - Otherwise it becomes active only when savedAt is strictly after the
//     active version's saved_at; on a tie the active version stays.
//   - There is a divergence when the base is not the active version, which
//     includes an empty base while the game already has an active version.
func Decide(active *Active, savedAt time.Time, baseVersionID *int64, activation Activation) Decision {
	if active == nil {
		return Decision{Activate: true}
	}
	conflict := baseVersionID == nil || *baseVersionID != active.ID
	var activate bool
	switch activation {
	case ActivateAlways:
		activate = true
	case ActivateNever:
		activate = false
	default:
		activate = savedAt.Truncate(Precision).After(active.SavedAt.Truncate(Precision))
	}
	return Decision{Activate: activate, Conflict: conflict}
}

// ClampSavedAt corrects a saved_at set in the future by a wrong clock.
//
// When reported is more than MaxClockSkew after received, the save is dated
// at received and skewed is true; the caller keeps the reported value and
// flags the device. A date in the past is kept as is: an upload may have
// waited in the client's queue.
func ClampSavedAt(reported, received time.Time) (savedAt time.Time, skewed bool) {
	if reported.Sub(received) > MaxClockSkew {
		return received.Truncate(Precision), true
	}
	return reported.Truncate(Precision), false
}
