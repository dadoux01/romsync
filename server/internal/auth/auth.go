// Package auth provides password hashing (Argon2id), random tokens and
// device pairing codes.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2Params are the Argon2id cost parameters.
type Argon2Params struct {
	Memory  uint32 // KiB
	Time    uint32
	Threads uint8
	KeyLen  uint32
	SaltLen uint32
}

// DefaultParams follows the OWASP recommendations, with more memory since a
// self-hosted service only handles a handful of logins.
var DefaultParams = Argon2Params{Memory: 64 * 1024, Time: 3, Threads: 2, KeyLen: 32, SaltLen: 16}

// ErrInvalidHash is returned for a malformed encoded hash.
var ErrInvalidHash = errors.New("auth: invalid password hash")

// HashPassword hashes password with Argon2id and returns it in the PHC
// string format: $argon2id$v=19$m=...,t=...,p=...$salt$hash.
func HashPassword(password string, p Argon2Params) (string, error) {
	salt := make([]byte, p.SaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := argon2.IDKey([]byte(password), salt, p.Time, p.Memory, p.Threads, p.KeyLen)
	b64 := base64.RawStdEncoding
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, p.Memory, p.Time, p.Threads, b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

// VerifyPassword reports whether password matches the encoded hash.
func VerifyPassword(password, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, ErrInvalidHash
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return false, ErrInvalidHash
	}
	var p Argon2Params
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.Memory, &p.Time, &p.Threads); err != nil {
		return false, ErrInvalidHash
	}
	b64 := base64.RawStdEncoding
	salt, err := b64.DecodeString(parts[4])
	if err != nil {
		return false, ErrInvalidHash
	}
	want, err := b64.DecodeString(parts[5])
	if err != nil || len(want) == 0 {
		return false, ErrInvalidHash
	}
	got := argon2.IDKey([]byte(password), salt, p.Time, p.Memory, p.Threads, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1, nil
}

// NewToken returns a random 256-bit token (base64url, no padding) and the
// hash under which it is stored.
func NewToken() (token, hash string, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", "", err
	}
	token = base64.RawURLEncoding.EncodeToString(b)
	return token, HashToken(token), nil
}

// HashToken returns the hex SHA-256 of a token. Tokens carry 256 bits of
// entropy, so a fast hash is enough: there is nothing to brute-force.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// PairCodeAlphabet excludes ambiguous characters (0/O, 1/I/L).
const PairCodeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

// PairCodeLen is the number of significant characters of a pairing code.
const PairCodeLen = 8

// NewPairCode returns a random pairing code, formatted as XXXX-XXXX.
func NewPairCode() (string, error) {
	b := make([]byte, PairCodeLen)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	// Rejection sampling keeps the distribution uniform.
	out := make([]byte, 0, PairCodeLen)
	n := byte(len(PairCodeAlphabet))
	limit := 256 - 256%int(n)
	for len(out) < PairCodeLen {
		for _, c := range b {
			if int(c) < limit && len(out) < PairCodeLen {
				out = append(out, PairCodeAlphabet[c%n])
			}
		}
		if _, err := rand.Read(b); err != nil {
			return "", err
		}
	}
	return string(out[:4]) + "-" + string(out[4:]), nil
}

// NormalizePairCode uppercases a user-typed code and removes separators.
// It returns "" when the result is not a well-formed code.
func NormalizePairCode(input string) string {
	var sb strings.Builder
	for _, r := range strings.ToUpper(input) {
		switch {
		case r == '-' || r == ' ':
			continue
		case strings.ContainsRune(PairCodeAlphabet, r):
			sb.WriteRune(r)
		default:
			return ""
		}
	}
	if sb.Len() != PairCodeLen {
		return ""
	}
	return sb.String()
}
