# IDontWannaLC

## Commands
- `bash scripts/check.sh` runs everything CI runs; `luajit tests/run.lua` runs only the engine unit tests; `luajit tests/smoke.lua .` runs the UI against the mock WoW API.
- `check.sh` needs `luajit` on PATH; there is no `lua`/`lua5.1`.

## Source of truth
- `PRD.md` decides scope: change it first, then code, tests and README. Cite requirement IDs (`R12`) in plans, tests and commit bodies.

## Done means
- `scripts/check.sh` passes. Nothing has run in the real game client, so never claim in-game behaviour is verified; say "smoke-tested against the mock".

## New files
- Add every new `.lua` to `IDontWannaLC.toc` in load order (Engine, Init, Data, then Core modules, then UI); the smoke test and `tests/toc_check.lua` read the `.toc`.

## Plans
- Plans live in `docs/superpowers/plans/YYYY-MM-DD-<name>.md`.

## Where new guidance goes
- See [docs/claude-code.md](docs/claude-code.md) before adding to this file, a rule, a skill or a hook.
