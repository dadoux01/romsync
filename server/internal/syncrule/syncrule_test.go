package syncrule

import (
	"testing"
	"time"
)

func ptr(v int64) *int64 { return &v }

func TestDecide(t *testing.T) {
	t0 := time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC)
	active := &Active{ID: 10, SavedAt: t0}

	cases := []struct {
		name    string
		active  *Active
		savedAt time.Time
		base    *int64
		mode    Activation
		want    Decision
	}{
		{"first save is active", nil, t0, nil, ActivateAuto, Decision{Activate: true}},
		{"first save with a stale base is active, no conflict", nil, t0, ptr(3), ActivateAuto, Decision{Activate: true}},
		{"newer save on the active base", active, t0.Add(time.Minute), ptr(10), ActivateAuto, Decision{Activate: true}},
		{"older save on the active base", active, t0.Add(-time.Minute), ptr(10), ActivateAuto, Decision{}},
		{"tie keeps the active version", active, t0, ptr(10), ActivateAuto, Decision{}},
		{"sub-millisecond difference is a tie", active, t0.Add(500 * time.Microsecond), ptr(10), ActivateAuto, Decision{}},
		{"newer divergent save wins with conflict", active, t0.Add(time.Hour), ptr(7), ActivateAuto, Decision{Activate: true, Conflict: true}},
		{"older divergent save loses with conflict", active, t0.Add(-time.Hour), ptr(7), ActivateAuto, Decision{Conflict: true}},
		{"empty base on an existing game is a divergence", active, t0.Add(time.Hour), nil, ActivateAuto, Decision{Activate: true, Conflict: true}},
		{"always: an older divergent save is activated", active, t0.Add(-time.Hour), ptr(7), ActivateAlways, Decision{Activate: true, Conflict: true}},
		{"never: a newer divergent save is archived", active, t0.Add(time.Hour), ptr(7), ActivateNever, Decision{Conflict: true}},
		{"never: a newer save on the active base is archived", active, t0.Add(time.Hour), ptr(10), ActivateNever, Decision{}},
		{"never: the first save is still active", nil, t0, nil, ActivateNever, Decision{Activate: true}},
	}
	for _, c := range cases {
		if got := Decide(c.active, c.savedAt, c.base, c.mode); got != c.want {
			t.Errorf("%s: got %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestClampSavedAt(t *testing.T) {
	recv := time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name     string
		reported time.Time
		want     time.Time
		skewed   bool
	}{
		{"exact", recv, recv, false},
		{"slightly in the future is tolerated", recv.Add(4 * time.Minute), recv.Add(4 * time.Minute), false},
		{"exactly 5 minutes is tolerated", recv.Add(5 * time.Minute), recv.Add(5 * time.Minute), false},
		{"far in the future is clamped", recv.Add(5*time.Minute + time.Second), recv, true},
		{"a year ahead is clamped", recv.AddDate(1, 0, 0), recv, true},
		{"the past is kept", recv.Add(-48 * time.Hour), recv.Add(-48 * time.Hour), false},
	}
	for _, c := range cases {
		got, skewed := ClampSavedAt(c.reported, recv)
		if !got.Equal(c.want) || skewed != c.skewed {
			t.Errorf("%s: got %v %v, want %v %v", c.name, got, skewed, c.want, c.skewed)
		}
	}
}
