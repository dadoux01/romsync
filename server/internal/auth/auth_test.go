package auth

import (
	"strings"
	"testing"
)

var fast = Argon2Params{Memory: 1024, Time: 1, Threads: 1, KeyLen: 32, SaltLen: 16}

func TestPasswordRoundTrip(t *testing.T) {
	h, err := HashPassword("correct horse", fast)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(h, "$argon2id$v=19$m=1024,t=1,p=1$") {
		t.Fatalf("unexpected encoding %q", h)
	}
	if ok, err := VerifyPassword("correct horse", h); err != nil || !ok {
		t.Fatalf("valid password rejected: %v", err)
	}
	if ok, _ := VerifyPassword("wrong", h); ok {
		t.Fatal("wrong password accepted")
	}
	h2, _ := HashPassword("correct horse", fast)
	if h == h2 {
		t.Fatal("salt must differ between hashes")
	}
}

func TestVerifyRejectsMalformedHash(t *testing.T) {
	for _, h := range []string{"", "plain", "$argon2i$v=19$m=1,t=1,p=1$c2FsdA$aGFzaA", "$argon2id$v=19$m=x$a$b"} {
		if _, err := VerifyPassword("x", h); err == nil {
			t.Errorf("expected an error for %q", h)
		}
	}
}

func TestTokens(t *testing.T) {
	tok, hash, err := NewToken()
	if err != nil {
		t.Fatal(err)
	}
	if len(tok) != 43 { // 32 bytes in base64url without padding
		t.Fatalf("unexpected token length %d", len(tok))
	}
	if hash != HashToken(tok) || len(hash) != 64 {
		t.Fatal("hash mismatch")
	}
	tok2, _, _ := NewToken()
	if tok == tok2 {
		t.Fatal("tokens must be random")
	}
}

func TestPairCodes(t *testing.T) {
	for i := 0; i < 200; i++ {
		c, err := NewPairCode()
		if err != nil {
			t.Fatal(err)
		}
		if len(c) != 9 || c[4] != '-' {
			t.Fatalf("bad format %q", c)
		}
		if NormalizePairCode(c) != c[:4]+c[5:] {
			t.Fatalf("normalisation of %q failed", c)
		}
		if strings.ContainsAny(c, "01OIL") {
			t.Fatalf("ambiguous character in %q", c)
		}
	}
	if NormalizePairCode(" k7qm-4xpa ") != "K7QM4XPA" {
		t.Fatal("lower case and spaces must be accepted")
	}
	for _, bad := range []string{"K7QM-4XP", "K7QM-4XPA1", "K7QM-0XPA", ""} {
		if NormalizePairCode(bad) != "" {
			t.Errorf("%q must be rejected", bad)
		}
	}
}
