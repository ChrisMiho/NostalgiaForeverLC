# Rebrand to NostalgiaForeverLC — design

## Intent
The guild wants the addon called NostalgiaForeverLC. The addon is still a proof of concept, so old saved settings and data can be dropped.

## Goals
- Rename the addon everywhere users or code see it: the `.toc` file and title, packaging, the global handle, saved data, the comm prefix, the slash command, chat tags, the PRD, README and agent guidance.
- Bump the version to 0.4.0.

## Non-goals
- Migrating old saved data (`IDontWannaLCDB` / `IDontWannaLCCharDB`). It is dropped.
- Working alongside old versions. The comm prefix changes, so old and new clients won't see each other.
- Renaming the GitHub repo or the local folder. That's the user's call.
- Editing historical plan docs in `docs/superpowers/plans/`.

## Approaches
1. **Full rename, fresh data (chosen).** Everything gets the new name and old data is lost. This is the simplest option and fine for a proof of concept.
2. Keep the old SavedVariables names and have users rename the WTF file by hand. Rejected: the user doesn't need the data.
3. Automatic migration by running both addons side by side. Rejected: fragile, and the data isn't needed.

## Decisions
| Item | Old | New |
|---|---|---|
| TOC file | `IDontWannaLC.toc` | `NostalgiaForeverLC.toc` |
| TOC title | I Don't Wanna LC | Nostalgia Forever LC |
| `.pkgmeta package-as` | IDontWannaLC | NostalgiaForeverLC |
| Global handle | `_G.IDontWannaLC` | `_G.NostalgiaForeverLC` |
| SavedVariables | `IDontWannaLCDB`, `IDontWannaLCCharDB` | `NostalgiaForeverLCDB`, `NostalgiaForeverLCCharDB` |
| Comm prefix | `IDWLC` | `NFLC` |
| Slash | `/idwlc` (primary), `/reserve` | `/nflc` (primary), with `/idwlc` and `/reserve` kept as aliases |
| Chat tag | `[IDWLC]` / `IDWLC:` | `[NFLC]` / `NFLC:` |
| Version | 0.3.0 | 0.4.0 |
| Display name in copy (PRD title, whisper text) | I Don't Wanna LC | Nostalgia Forever LC |
| Frame / StaticPopup global names | `IDWLC_*` | `NFLC_*` |
| Wishlist export string | `IDWLC1!…` | `NFLC1!…` (old export strings stop importing) |
| Frame-position field | `f.idwlcName` | `f.nflcName` |

The order follows CLAUDE.md: PRD first, then code, tests, README, CLAUDE.md and `.claude/rules`.

## Done
`scripts/check.sh` passes. A grep for `IDontWanna|IDWLC` finds only the historical plan docs, the `/idwlc` alias, and this spec.
