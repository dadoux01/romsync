# Conversion profiles

Each file describes how an emulator or flashcard stores a save,
relative to the canonical format kept by the server (the raw content of the
save chip). Profiles are shared by the Flutter client and the 3DS homebrew,
so that a contributor can add an emulator without touching their code.

They are JSON rather than YAML so that the 3DS homebrew (C) can read them with
a small parser.

| Field | Meaning |
| --- | --- |
| `id` | Identifier used by the API (`?profile=<id>`) |
| `status` | `confirmed`, or `to_verify` until round-trip tests pass |
| `kind` | `file` (default) or `tree`: a save made of a folder, read and written as its canonical archive (docs/SPEC.md, "Saves en dossier") |
| `systems` | Consoles whose saves the profile converts (`nds`, `gba`; docs/SPEC.md, "Multi-consoles") |
| `extension` | File extension, with its dot |
| `location` | Where the emulator looks for the file (informational) |
| `header` / `footer` | Bytes added before / after the raw data, `null` when none |
| `footer.optional` | The footer is only there when the file size modulo `footer.size_modulo` equals its length (mGBA's cartridge clock); it is removed on read and never written |
| `size.output` | `exact` (raw size) or `pad_min` (padded with `pad_byte` up to at least `pad_to` bytes and the game's chip size; never cut) |

The server implements the `raw`, `desmume`, `flashcard` and `mgba` profiles in Go
(`server/internal/convert`); `TestProfilesMatchCode` fails if these files and
the code disagree.
