# Rebrand to NostalgiaForeverLC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the addon from IDontWannaLC to NostalgiaForeverLC everywhere, with no data migration.

**Architecture:** Mechanical token rename, applied in this order: PRD, then code and tests, then docs. One smoke check pins the slash aliases.

**Tech Stack:** Lua 5.1 / LuaJIT, WoW addon API (mocked in `tests/smoke.lua`).

**Spec:** `docs/superpowers/specs/2026-11-17-rebrand-nostalgiaforeverlc-design.md`

## Global Constraints
- Token map, applied to everything except `docs/superpowers/plans/*` (history) and the spec:
  `IDontWannaLC`→`NostalgiaForeverLC`, `IDONTWANNALC`→`NOSTALGIAFOREVERLC`, `IDWLC`→`NFLC`, `idwlcName`→`nflcName`, `/idwlc`→`/nflc`, `I Don't Wanna LC`→`Nostalgia Forever LC`.
- `/idwlc` stays registered as an alias (`SLASH_NOSTALGIAFOREVERLC3`), and `/reserve` stays as `…2`.
- `.toc` version is `0.4.0`, and README status is `v0.4.0`. Smoke-test peer versions (`VER^0.3.0` for Bob) stay as they are because they stand for an older peer.
- Cite the requirements touched in commit bodies: R1, R33a, and §comm (the prefix line).

## Review Focus
- `/idwlc` typed by a guildie out of habit still opens the addon. Pinned by the smoke check in Task 2.
- `ADDON_LOADED` fires with the new folder name `NostalgiaForeverLC`, or init never runs. Covered by the smoke test's `event("ADDON_LOADED", …)` after the rename.
- Comm messages under the old prefix `IDWLC` are ignored. This is accepted (non-goal), so no test.
- An old `IDWLC1!` wishlist export no longer imports. This is accepted (non-goal), so no test.

---

### Task 1: PRD

**Files:** Modify `PRD.md` (title line 1, R1 line 25, R33a line 79, comm prefix line 146).

- [ ] Apply the token map. R1 becomes "(`/nflc`, `/reserve`; `/idwlc` kept as an alias)".
- [ ] Commit: `docs(prd): rename addon to NostalgiaForeverLC (R1, R33a)`.

### Task 2: Code and tests

**Files:** Rename `IDontWannaLC.toc`→`NostalgiaForeverLC.toc` (`git mv`). Modify `.pkgmeta`, `Core/*.lua`, `UI/*.lua`, `tests/smoke.lua`, `tests/toc_check.lua` and `tests/run.lua`.

- [ ] **Failing test:** in `tests/smoke.lua`, after the addon loads, add
  ```lua
  check(G.SLASH_NOSTALGIAFOREVERLC1 == "/nflc" and G.SLASH_NOSTALGIAFOREVERLC2 == "/reserve"
      and G.SLASH_NOSTALGIAFOREVERLC3 == "/idwlc" and G.SlashCmdList.NOSTALGIAFOREVERLC, "slash /nflc + aliases registered")
  ```
- [ ] Run `luajit tests/smoke.lua .`. Expected: FAIL on that check.
- [ ] Apply the token map to the files above, with `git mv` for the `.toc`. Set `## Version: 0.4.0` and `## Title: Nostalgia Forever LC`. Re-add `SLASH_NOSTALGIAFOREVERLC3 = "/idwlc"` in `Core/Slash.lua`, because the map turns the old `/idwlc` line into `/nflc`.
- [ ] Run `bash scripts/check.sh`. Expected: all four steps pass.
- [ ] Commit: `Rename addon to NostalgiaForeverLC (R1, R33a, comm prefix)`.

### Task 3: Docs and agent guidance

**Files:** Modify `README.md`, `CLAUDE.md` and `.claude/rules/comm.md`.

- [ ] Apply the token map. The README slash table row becomes `/nflc` or `/reserve` (`/idwlc` still works). The install path becomes `AddOns/NostalgiaForeverLC`. Add a line saying settings from IDontWannaLC are not carried over.
- [ ] Verify with `bash scripts/check.sh`, then `grep -rnE "IDontWanna|IDWLC|idwlc" --exclude-dir=.git . | grep -v docs/superpowers`. Expected: only the `/idwlc` alias mentions remain.
- [ ] Commit: `docs: rename to NostalgiaForeverLC in README and guidance`.
