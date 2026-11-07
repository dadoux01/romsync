// Package chipdb knows the save size of Nintendo DS games by game code.
//
// chipsizes.txt is generated from melonDS's ROM list (GPL-3.0-or-later,
// compatible with RomSync's AGPL-3.0 through section 13 of both licenses);
// see gen/main.go to regenerate it. melonDS has no 32 KiB entry: games with a
// 32 KiB FRAM are listed at 64 KiB, which the size rules of the server absorb
// (a smaller first save is accepted, see docs/SPEC.md "Taille réelle").
package chipdb

import (
	_ "embed"
	"strconv"
	"strings"
	"sync"
)

//go:embed chipsizes.txt
var data string

var (
	once  sync.Once
	sizes map[string]int64
)

func load() {
	sizes = make(map[string]int64, 7000)
	for _, line := range strings.Split(data, "\n") {
		if line == "" || line[0] == '#' {
			continue
		}
		code, size, ok := strings.Cut(line, " ")
		if !ok {
			continue
		}
		n, err := strconv.ParseInt(size, 10, 64)
		if err != nil || n <= 0 {
			continue
		}
		sizes[code] = n
	}
}

// Size returns the save size of a game, when known. Only 4-character
// cartridge codes can be known.
func Size(code string) (int64, bool) {
	once.Do(load)
	n, ok := sizes[code]
	return n, ok
}

// Len returns the number of known games.
func Len() int {
	once.Do(load)
	return len(sizes)
}
