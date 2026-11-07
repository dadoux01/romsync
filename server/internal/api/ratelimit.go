package api

import (
	"sync"
	"time"
)

// rateLimiter allows a fixed number of attempts per key over a sliding window.
type rateLimiter struct {
	mu       sync.Mutex
	limit    int
	window   time.Duration
	attempts map[string][]time.Time
	lastGC   time.Time
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{limit: limit, window: window, attempts: map[string][]time.Time{}}
}

// allow records an attempt for key at now and reports whether it is allowed.
func (l *rateLimiter) allow(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	cutoff := now.Add(-l.window)
	if now.Sub(l.lastGC) > l.window {
		for k, ts := range l.attempts {
			if len(ts) == 0 || !ts[len(ts)-1].After(cutoff) {
				delete(l.attempts, k)
			}
		}
		l.lastGC = now
	}

	ts := l.attempts[key]
	kept := ts[:0]
	for _, t := range ts {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= l.limit {
		l.attempts[key] = kept
		return false
	}
	l.attempts[key] = append(kept, now)
	return true
}
