---
name: add-forever-raid
description: "Add a new WoW Forever raid (or its loot table once published): data entry, card art, tests, README and PRD."
---

1. `Data/Forever.lua`: `add({ key = "F_<SHORT>", name, size, instanceIDs = {}, instanceNames = { "<exact in-game instance name>" } })`. `bosses` stays empty until the loot table is published; then fill it in the `Data/Raids.lua` shape. Set `lootFrom = "<classic key>"` only when borrowing Classic loot.
2. `Data/RaidMeta.lua`: add `F_<SHORT> = { icon = "Interface\\Icons\\...", color = { r, g, b } }`. Add `artItem` once a signature item ID is known, and `names` if the game uses other instance names.
3. `tests/smoke.lua`, "Forever client" block (starts near "Forever client: Forever raids first"): it asserts list order (`choiceKeys.F_BARROW == 1`) and reads classic cards by position (`fcards[4]`, the first classic card, i.e. the number of Forever raids + 1). Update those if the new raid changes them, and add `GetBossCount`/`GetBosses` checks for it.
4. `README.md` "Supported raids" line for the Forever client. In `PRD.md` §6 Open questions, adjust the "loot tables, boss lists and instance IDs are unpublished" bullet if the new raid's data is still unpublished (or remove what is now known).
5. Run `bash scripts/check.sh` and show its output.
