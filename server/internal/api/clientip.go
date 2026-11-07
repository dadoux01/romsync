package api

import (
	"net"
	"net/http"
	"net/netip"
	"strings"
)

// clientIP returns the address of the client. X-Forwarded-For is only honoured
// when the TCP peer is a trusted proxy; the right-most untrusted address of the
// header is then used, so a client cannot spoof its address by prepending one.
func clientIP(r *http.Request, trusted []netip.Prefix) string {
	peer := peerAddr(r)
	if !peer.IsValid() {
		return r.RemoteAddr
	}
	if !isTrusted(peer, trusted) {
		return peer.String()
	}
	xff := r.Header.Values("X-Forwarded-For")
	if len(xff) == 0 {
		return peer.String()
	}
	parts := strings.Split(strings.Join(xff, ","), ",")
	for i := len(parts) - 1; i >= 0; i-- {
		a, err := netip.ParseAddr(strings.TrimSpace(parts[i]))
		if err != nil {
			break
		}
		a = a.Unmap()
		if !isTrusted(a, trusted) {
			return a.String()
		}
		peer = a
	}
	return peer.String()
}

func peerAddr(r *http.Request) netip.Addr {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	a, err := netip.ParseAddr(host)
	if err != nil {
		return netip.Addr{}
	}
	return a.Unmap()
}

func isTrusted(a netip.Addr, trusted []netip.Prefix) bool {
	for _, p := range trusted {
		if p.Contains(a) {
			return true
		}
	}
	return false
}
