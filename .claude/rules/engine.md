---
paths:
  - "Core/Engine.lua"
  - "tests/engine_spec.lua"
  - "tests/run.lua"
---
- `Core/Engine.lua` uses no WoW API or WoW globals: `tests/run.lua` loads it in plain LuaJIT.
- Test helpers are the globals `describe`, `it`, `eq`, `truthy`, `falsy` defined in `tests/run.lua`.
- A new spec file runs only once it is added to the `specs` list in `tests/run.lua`.
