# Claude Code Practices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codify the Claude Code best practices in the repo so every future agent session starts with the knowledge it can't read from the code, has one pass/fail check to run, and is stopped by the harness from breaking the few rules that have no exceptions.

**Architecture:** Three layers, following the doc's deterministic / non-deterministic split. (1) **One check** — `scripts/check.sh` runs everything CI runs, plus a `.toc` consistency check, and CI calls the same script so local and CI can't drift. (2) **Enforcement** — committed `.claude/settings.json` with a `Stop` hook that runs the check and a `PreToolUse` hook that blocks hand edits to the generated loot table. (3) **Guidance** — a short `CLAUDE.md`, path-scoped `.claude/rules/`, one procedure skill, one read-only reviewer subagent, and `docs/claude-code.md` explaining where each kind of new rule belongs.

**Tech Stack:** Bash (Git Bash on Windows, ubuntu in CI), LuaJIT, Claude Code project config (`CLAUDE.md`, `.claude/settings.json`, `.claude/rules/`, `.claude/skills/`, `.claude/agents/`), GitHub Actions.

**Spec:** https://code.claude.com/docs/en/best-practices (fetched 2026-11-17). Project facts come from [PRD.md](../../../PRD.md) §5 and the current code.

## Global Constraints

- Only write down what an agent can't find by reading the repo, or would otherwise rediscover every session. No architecture or file-layout descriptions (README already has the layout).
- `CLAUDE.md` stays under **60 lines**; plain wording, no IMPORTANT / ALL CAPS.
- Hooks only for zero-exception rules. The enforced set in this plan is exactly two hooks; anything else is guidance.
- Hook commands must run under Git Bash on Windows **and** bash on Linux. No `jq` (not installed on the dev machine); parse hook JSON with `grep`/`sed` or LuaJIT.
- Hook commands reference scripts as `"$CLAUDE_PROJECT_DIR"/scripts/...` so they work from any cwd.
- `scripts/check.sh` finishes in well under 5 s (current suite: ~0.1 s) — it runs on every Stop.
- Nothing added to the shipped addon: `scripts/`, `.claude/`, `CLAUDE.md` are excluded via `.pkgmeta` `ignore`.
- Commit messages: imperative subject, bullet body, ending with the `Co-Authored-By` trailer the session supplies.

## Review Focus

1. **Stop hook on a session that changed nothing while the tree is already red** — it must still block with the failing output (that's the point), and must not loop forever; the harness cap (8 blocks) applies. Task 2 verification covers the blocking output being on stderr.
2. **Windows paths in hook input** — `tool_input.file_path` arrives as `C:\\Coding\\IDontWannaLC\\Data\\Raids.lua` (escaped backslashes, absolute). The protect hook must block it, and must not block `Data/RaidMeta.lua` or `Data/Raids_notes.md`. Task 2 test.
3. **A new Lua file added to `Core/`, `Data/` or `UI/` but not to the `.toc`** — it never loads in game, and today the smoke test also hard-codes its own file list, so nothing notices. The check must fail, naming the file. Task 1 test.
4. **check.sh run from a subdirectory** (agents often `cd tests`) — must still find the repo root. Task 1 test.
5. **Stale guidance** — a rule file whose `paths:` glob matches no file silently never loads. Task 3 verification lists the matches for each glob.

---

### Task 1: One check script, shared by agents and CI

**Files:**
- Create: `scripts/check.sh`, `tests/toc_check.lua`
- Modify: `tests/smoke.lua:122-126` (file list), `.github/workflows/test.yml`, `README.md` (Development section), `.pkgmeta`

**Interfaces — Produces:**
- `bash scripts/check.sh [--quiet]` → exit 0 when all pass, 1 otherwise. Steps in order: parse check (`luajit -bl` over `Core/*.lua Data/*.lua UI/*.lua`), `luajit tests/toc_check.lua`, `luajit tests/run.lua`, `luajit tests/smoke.lua .`. Without `--quiet` it streams each step's output. With `--quiet` it prints nothing on success and, on failure, prints `check.sh: <step name> failed` plus that step's output to **stderr**. It `cd`s to the repo root (`"$(dirname "$0")/.."`) first.
- `luajit tests/toc_check.lua` → exit 0, or exit 1 printing `toc_check: <path> not in IDontWannaLC.toc` / `toc_check: <path> listed in IDontWannaLC.toc but missing`.
- `tests/smoke.lua` loads its files from `IDontWannaLC.toc` (non-empty lines not starting with `#`, `\` → `/`) instead of the hard-coded list.

- [ ] **Step 1: Write `tests/toc_check.lua`** — reads the `.toc`, lists `Core/*.lua`, `Data/*.lua`, `UI/*.lua` on disk (use `io.popen('ls Core/*.lua Data/*.lua UI/*.lua')`, which works in Git Bash and CI), reports both directions.
- [ ] **Step 2: Prove it catches drift**
  Run: `touch Core/Orphan.lua && luajit tests/toc_check.lua; echo "exit=$?"; rm Core/Orphan.lua`
  Expected: `toc_check: Core/Orphan.lua not in IDontWannaLC.toc` and `exit=1`. Then `luajit tests/toc_check.lua; echo "exit=$?"` → `exit=0`.
- [ ] **Step 3: Make `tests/smoke.lua` read the `.toc`** — replace the `files` table at lines 122-126 with a parse of `ROOT .. "/IDontWannaLC.toc"`.
  Run: `luajit tests/smoke.lua .` → last lines `ERRORS 0`, exit 0.
- [ ] **Step 4: Write `scripts/check.sh`** per the Interfaces block (`set -u`, a `step <name> <command…>` helper that captures output in `--quiet` mode).
- [ ] **Step 5: Verify pass, fail and cwd cases**
  - `bash scripts/check.sh` → shows `78 passed, 0 failed` and `ERRORS 0`, exit 0.
  - `bash scripts/check.sh --quiet; echo "exit=$?"` → only `exit=0`.
  - `cd tests && bash ../scripts/check.sh --quiet; echo "exit=$?"; cd ..` → `exit=0`.
  - `echo 'local x =' >> Core/Stats.lua && bash scripts/check.sh --quiet; echo "exit=$?"; git checkout Core/Stats.lua` → stderr starts `check.sh: parse failed`, names `Core/Stats.lua`, `exit=1`.
- [ ] **Step 6: Point CI at the script** — `.github/workflows/test.yml`: keep checkout and LuaJIT install, replace the three run steps with one `- name: Checks` / `run: bash scripts/check.sh`. Add `scripts` to `.pkgmeta` `ignore`. In `README.md` → Development, replace the two `luajit` lines with `bash scripts/check.sh` (one sentence: it runs what CI runs).
- [ ] **Step 7: Commit**
  ```bash
  git add scripts/check.sh tests/toc_check.lua tests/smoke.lua .github/workflows/test.yml README.md .pkgmeta
  git commit -m "Add scripts/check.sh as the single check for agents and CI"
  ```

### Task 2: Harness enforcement (hooks, permissions, local files)

**Files:**
- Create: `.claude/settings.json`, `scripts/hooks/protect-generated.sh`
- Modify: `.gitignore`, `.pkgmeta`

**Interfaces:**
- Consumes: `bash scripts/check.sh --quiet` (Task 1).
- Produces: `scripts/hooks/protect-generated.sh` reads PreToolUse JSON on stdin; if `tool_input.file_path`, after unescaping `\\` and turning `\` into `/`, ends with `/Data/Raids.lua` or equals `Data/Raids.lua`, it prints to stderr `Data/Raids.lua is generated by tools/gen_classic_raids.lua. Edit the generator or Data/Forever.lua instead, then regenerate (see README > Supported raids).` and exits 2; otherwise exits 0.

`.claude/settings.json` content (exact):

```json
{
  "permissions": {
    "allow": [
      "Bash(bash scripts/check.sh)",
      "Bash(bash scripts/check.sh --quiet)",
      "Bash(luajit tests/*)",
      "Bash(luajit -bl *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/protect-generated.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/check.sh --quiet || exit 2" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 1: Write `scripts/hooks/protect-generated.sh`.**
- [ ] **Step 2: Test it with piped input**
  ```bash
  h=scripts/hooks/protect-generated.sh
  echo '{"tool_input":{"file_path":"C:\\\\Coding\\\\IDontWannaLC\\\\Data\\\\Raids.lua"}}' | bash $h; echo "win=$?"
  echo '{"tool_input":{"file_path":"/home/u/IDontWannaLC/Data/Raids.lua"}}' | bash $h; echo "posix=$?"
  echo '{"tool_input":{"file_path":"Data/RaidMeta.lua"}}' | bash $h; echo "meta=$?"
  echo '{"tool_input":{"file_path":"Data/Raids_notes.md"}}' | bash $h; echo "notes=$?"
  ```
  Expected: `win=2`, `posix=2` (each with the message on stderr), `meta=0`, `notes=0`.
- [ ] **Step 3: Write `.claude/settings.json`** as above. Append `CLAUDE.local.md` and `.claude/settings.local.json` to `.gitignore`. Add `.claude` and `CLAUDE.md` to `.pkgmeta` `ignore`.
- [ ] **Step 4: Verify in a live session** (fresh `claude` in the repo, accept the trust dialog):
  - Ask: "add a comment line to the top of Data/Raids.lua" → the edit is refused with the generator message.
  - Ask: "append `local x =` to Core/Stats.lua and stop" → the turn does not end; Claude receives `check.sh: parse failed …` and reverts. `/hooks` lists both hooks.
- [ ] **Step 5: Commit**
  ```bash
  git add .claude/settings.json scripts/hooks/protect-generated.sh .gitignore .pkgmeta
  git commit -m "Enforce the check on Stop and protect the generated loot table"
  ```

### Task 3: Guidance — CLAUDE.md, scoped rules, maintainer guide

**Files:**
- Create: `CLAUDE.md`, `.claude/rules/engine.md`, `.claude/rules/ui.md`, `.claude/rules/comm.md`, `.claude/rules/data.md`, `docs/claude-code.md`

**Interfaces:**
- Consumes: `scripts/check.sh` (Task 1), the two hooks (Task 2) — CLAUDE.md names the command, not the enforcement.

`CLAUDE.md` holds exactly these sections and facts (wording is the implementer's; keep each a single line):
- **Commands:** `bash scripts/check.sh` (everything CI runs); `luajit tests/run.lua` (engine unit tests only); `luajit tests/smoke.lua .` (UI against the mock WoW API). LuaJIT is on PATH in Git Bash on Windows; there is no `lua`/`lua5.1`.
- **Source of truth:** `PRD.md` decides scope; change it first, then code, tests, README. Cite requirement IDs (`R12`) in plans, tests and commit bodies.
- **Done means:** check.sh passes. Nothing has run in the real game client — never claim in-game behaviour is verified; say "smoke-tested against the mock".
- **New files:** add every new `.lua` to `IDontWannaLC.toc` in load order (Engine, Init, Data, then Core modules, then UI). The smoke test and `tests/toc_check.lua` read the `.toc`.
- **Plans:** live in `docs/superpowers/plans/YYYY-MM-DD-<name>.md`.
- **Where new guidance goes:** see `docs/claude-code.md` (a plain link, not an `@` import).

`.claude/rules/*.md` — each starts with a `paths:` frontmatter list and holds only these facts:
- `engine.md` (`Core/Engine.lua`, `tests/engine_spec.lua`, `tests/run.lua`): no WoW API or WoW globals in Engine — it is loaded by plain LuaJIT; test helpers are `describe/it/eq/truthy/falsy` from `tests/run.lua`; a new spec file must be added to the `specs` list in `tests/run.lua`.
- `ui.md` (`UI/**/*.lua`, `tests/smoke.lua`): the smoke mock returns a function for any unknown frame field or API, so a missing mock fails silently — add new WoW API to the mock; never keep boolean state in frame fields that may be unset, use locals; use only API present on both interfaces `16001` and `11509`, feature-detected as `(C_X and C_X.Fn) or _G.Fn` (see `Core/Init.lua`); assert with `check(cond, msg)`.
- `comm.md` (`Core/Comm.lua`): messages < 255 bytes, `^`-separated, prefix `IDWLC`; raid messages accepted only over the RAID channel, never whispers (R70).
- `data.md` (`Data/**`, `tools/**`): `Data/Raids.lua` is generated (a hook blocks edits; regenerate with the command in README); new Forever raids follow the `add-forever-raid` skill; every raid key needs an entry in `Data/RaidMeta.lua` (the smoke test fails otherwise).

`docs/claude-code.md` — the maintainer guide (target ≤ 80 lines), with:
- A "where does this go" table: fact Claude can't find & matters everywhere → `CLAUDE.md`; matters in one area → `.claude/rules/<area>.md` with `paths:`; a multi-step procedure → `.claude/skills/<name>/SKILL.md` (`disable-model-invocation: true` if it has side effects outside the repo); a rule with zero exceptions → hook in `.claude/settings.json`; something that must never be read/run → `permissions.deny`; personal preference → `CLAUDE.local.md` (gitignored).
- The two tests before writing anything down: could an agent find it by reading the code, and would it actually look? Both yes → leave it out.
- What's enforced today (the two hooks + CI) and why each has zero exceptions.
- The session habits that can't be codified: specific prompts naming files and "done"; brainstorm → PRD/spec → fresh session to build; `/clear` between unrelated tasks and after two failed corrections; ask for evidence (command + output); review with the `prd-reviewer` agent, "skip style".
- Deliberately not added yet, and the trigger for adding: a release skill (once a packaging/release process exists), a `.worktreeinclude` (once there are gitignored files a checkout needs), MCP servers (none needed; `gh` covers GitHub).
- Maintenance: when Claude gets something wrong twice, add a line in the right place from the table; when `CLAUDE.md` passes 60 lines, move area facts into rules; run `/doctor prompt-audit` after big refactors.

- [ ] **Step 1: Write `CLAUDE.md`, the four rule files and `docs/claude-code.md`** as specified.
- [ ] **Step 2: Verify size and that every referenced path exists**
  Run: `wc -l CLAUDE.md` → under 60.
  Run: `for p in $(grep -ohE '\b(Core|Data|UI|tests|tools|scripts|docs)/[A-Za-z0-9_./-]+\.(lua|sh|md)\b' CLAUDE.md .claude/rules/*.md docs/claude-code.md | sort -u); do [ -e "$p" ] || echo "MISSING $p"; done` → no output (skip the `YYYY-MM-DD` plan pattern if it matches).
- [ ] **Step 3: Verify every `paths:` glob matches files** — for each glob in the four rule files run `git ls-files '<glob>'` → each prints at least one path.
- [ ] **Step 4: Verify the rules load** — in a fresh session ask "open Core/Comm.lua and tell me the message size limit", then run `/context all` → `.claude/rules/comm.md` is listed and the answer is "< 255 bytes".
- [ ] **Step 5: Commit**
  ```bash
  git add CLAUDE.md .claude/rules docs/claude-code.md
  git commit -m "Add CLAUDE.md, path-scoped rules and a guide to where agent guidance lives"
  ```

### Task 4: Procedure skill and read-only PRD reviewer

**Files:**
- Create: `.claude/skills/add-forever-raid/SKILL.md`, `.claude/agents/prd-reviewer.md`
- Modify: `docs/claude-code.md` (one line each under what exists)

**Interfaces:**
- Consumes: `bash scripts/check.sh` (Task 1); `docs/claude-code.md` (Task 3).
- Produces: skill `add-forever-raid` (model-invocable — it only edits repo files); subagent `prd-reviewer`.

`add-forever-raid` frontmatter: `name: add-forever-raid`, `description: Add a new WoW Forever raid (or its loot table once published): data entry, card art, tests, README and PRD.` Body steps, in order:
1. `Data/Forever.lua`: `add({ key = "F_<SHORT>", name, size, instanceIDs = {}, instanceNames = { "<exact in-game instance name>" } })`; `bosses` stays empty until the loot table is published, then fill it in the `Data/Raids.lua` shape; `lootFrom = "<classic key>"` only when borrowing classic loot.
2. `Data/RaidMeta.lua`: `F_<SHORT> = { icon = "Interface\\Icons\\…", color = { r, g, b } }` (+ `artItem` once a signature item ID is known, `names` if the game uses other instance names).
3. `tests/smoke.lua` Forever block (~line 940): update the expected ordering checks if the new raid changes which raid is listed first.
4. `README.md` → Supported raids, and `PRD.md` → §6 Open questions if the raid's data is still unpublished.
5. Run `bash scripts/check.sh` and show its output.

`prd-reviewer` (exact frontmatter): `name: prd-reviewer`, `description: Reviews a diff against PRD.md requirement IDs. Use after implementing a plan task or before opening a PR.`, `tools: Read, Grep, Glob, Bash`, `model: sonnet`. Body: you didn't write this code; get the diff with `git diff main...HEAD` (or the range you're given); for each PRD requirement the diff touches, say implemented / partial / missing with file:line; check each touched requirement has a test in `tests/`; flag PRD §5 constraint violations; report only gaps that affect correctness, skip style; never edit files.

- [ ] **Step 1: Write both files.** Add a line for each to `docs/claude-code.md`.
- [ ] **Step 2: Verify the skill steps match the code** — every file and field the skill names exists: `grep -n "instanceNames\|lootFrom" Data/Forever.lua` and `grep -n "artItem\|names" Data/RaidMeta.lua` each print matches.
- [ ] **Step 3: Verify discovery** — in a fresh session, `/agents` lists `prd-reviewer` and the skill list shows `add-forever-raid`. Dry-run the reviewer: "have the prd-reviewer check `git diff 730f67a 4ec0030` against PRD.md" → it returns per-requirement findings and makes no edits (`git status` clean).
- [ ] **Step 4: Commit**
  ```bash
  git add .claude/skills .claude/agents docs/claude-code.md
  git commit -m "Add add-forever-raid skill and read-only prd-reviewer agent"
  ```
