package retention

import (
	"slices"
	"testing"
	"time"
)

var now = time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC) // a Saturday

// hourly returns n versions, one per hour going back from now, ids 1..n
// (id 1 is the newest).
func hourly(n int) []Version {
	vs := make([]Version, n)
	for i := range vs {
		vs[i] = Version{ID: int64(i + 1), SavedAt: now.Add(-time.Duration(i) * time.Hour)}
	}
	return vs
}

func sorted(ids []int64) []int64 {
	out := slices.Clone(ids)
	slices.Sort(out)
	return out
}

func TestPolicyValidate(t *testing.T) {
	for _, ok := range []Policy{{Mode: "all"}, {Mode: "smart"}, {Mode: "last_n", N: 1}, {Mode: "days", N: 30}} {
		if err := ok.Validate(); err != nil {
			t.Errorf("%+v: %v", ok, err)
		}
	}
	for _, bad := range []Policy{{Mode: ""}, {Mode: "forever"}, {Mode: "last_n"}, {Mode: "days", N: -1}, {Mode: "all", N: 3}} {
		if err := bad.Validate(); err == nil {
			t.Errorf("%+v must be invalid", bad)
		}
	}
	p, err := Parse(`{"mode":"last_n","n":10}`)
	if err != nil || p != (Policy{Mode: "last_n", N: 10}) || p.Encode() != `{"mode":"last_n","n":10}` {
		t.Fatalf("parse/encode: %+v %v", p, err)
	}
}

func TestAllKeepsEverything(t *testing.T) {
	if got := Select(hourly(1000), Policy{Mode: ModeAll}, now); len(got) != 0 {
		t.Fatalf("all removed %d versions", len(got))
	}
}

func TestLastN(t *testing.T) {
	vs := hourly(6)
	got := Select(vs, Policy{Mode: ModeLastN, N: 3}, now)
	if !slices.Equal(sorted(got), []int64{4, 5, 6}) {
		t.Fatalf("got %v", got)
	}
}

func TestDays(t *testing.T) {
	vs := []Version{
		{ID: 1, SavedAt: now.Add(-1 * time.Hour)},
		{ID: 2, SavedAt: now.Add(-47 * time.Hour)},
		{ID: 3, SavedAt: now.Add(-48 * time.Hour)}, // exactly 2 days: removed
		{ID: 4, SavedAt: now.Add(-100 * time.Hour)},
	}
	got := Select(vs, Policy{Mode: ModeDays, N: 2}, now)
	if !slices.Equal(sorted(got), []int64{3, 4}) {
		t.Fatalf("got %v", got)
	}
}

func TestActiveAndPinnedAreNeverRemoved(t *testing.T) {
	vs := hourly(10)
	vs[9].Active = true // the oldest is active (restored)
	vs[5].Pinned = true
	for _, p := range []Policy{{Mode: ModeLastN, N: 1}, {Mode: ModeDays, N: 1}, {Mode: ModeSmart}} {
		vs := slices.Clone(vs)
		for i := range vs {
			vs[i].SavedAt = vs[i].SavedAt.AddDate(-1, 0, 0) // everything is old
		}
		got := Select(vs, p, now)
		if slices.Contains(got, 10) || slices.Contains(got, 6) {
			t.Fatalf("%s removed a protected version: %v", p.Mode, got)
		}
	}
}

func TestSmart(t *testing.T) {
	day := 24 * time.Hour
	vs := []Version{
		// Under 7 days: everything kept.
		{ID: 1, SavedAt: now.Add(-1 * time.Hour)},
		{ID: 2, SavedAt: now.Add(-2 * time.Hour)},
		{ID: 3, SavedAt: now.Add(-6*day - 23*time.Hour)},
		// 7 to 30 days: the most recent per UTC day.
		{ID: 10, SavedAt: time.Date(2026, 10, 25, 20, 0, 0, 0, time.UTC)},
		{ID: 11, SavedAt: time.Date(2026, 10, 25, 9, 0, 0, 0, time.UTC)},
		{ID: 12, SavedAt: time.Date(2026, 10, 25, 0, 30, 0, 0, time.UTC)},
		{ID: 13, SavedAt: time.Date(2026, 10, 24, 23, 59, 0, 0, time.UTC)},
		// Beyond 30 days: the most recent per ISO week.
		// 2026-09-28 (Mon) to 2026-10-04 (Sun) is ISO week 40.
		{ID: 20, SavedAt: time.Date(2026, 10, 4, 22, 0, 0, 0, time.UTC)},
		{ID: 21, SavedAt: time.Date(2026, 9, 30, 10, 0, 0, 0, time.UTC)},
		{ID: 22, SavedAt: time.Date(2026, 9, 28, 0, 0, 0, 0, time.UTC)},
		// Week 39.
		{ID: 23, SavedAt: time.Date(2026, 9, 27, 23, 0, 0, 0, time.UTC)},
		// Week 1 of 2026 starts on Monday 2025-12-29: same bucket.
		{ID: 30, SavedAt: time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)},
		{ID: 31, SavedAt: time.Date(2025, 12, 29, 0, 0, 0, 0, time.UTC)},
	}
	got := Select(vs, Policy{Mode: ModeSmart}, now)
	want := []int64{11, 12, 21, 22, 31}
	if !slices.Equal(sorted(got), want) {
		t.Fatalf("got %v, want %v", sorted(got), want)
	}
}

func TestSmartBoundaries(t *testing.T) {
	day := 24 * time.Hour
	// Two versions on the same UTC day, exactly 7 days old and just under:
	// the younger one is in the keep-all band, the older one is the most
	// recent of its day within the daily band, so both are kept.
	vs := []Version{
		{ID: 1, SavedAt: now.Add(-7*day + time.Minute)},
		{ID: 2, SavedAt: now.Add(-7 * day)},
		{ID: 3, SavedAt: now.Add(-7*day - time.Minute)},
	}
	got := Select(vs, Policy{Mode: ModeSmart}, now)
	if !slices.Equal(got, []int64{3}) {
		t.Fatalf("got %v", got)
	}
}

func TestSelectIsOrderIndependent(t *testing.T) {
	vs := hourly(50)
	rev := slices.Clone(vs)
	slices.Reverse(rev)
	a := sorted(Select(vs, Policy{Mode: ModeLastN, N: 7}, now))
	b := sorted(Select(rev, Policy{Mode: ModeLastN, N: 7}, now))
	if !slices.Equal(a, b) {
		t.Fatal("selection must not depend on input order")
	}
}
