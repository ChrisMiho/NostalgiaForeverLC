---
paths:
  - "Data/**"
  - "tools/**"
---
- `Data/Raids.lua` is generated: a hook blocks edits to it; regenerate it with the `tools/gen_classic_raids.lua` command in README.
- New Forever raids follow the `add-forever-raid` skill.
- Every raid key needs an entry in `Data/RaidMeta.lua`; the smoke test fails otherwise.
