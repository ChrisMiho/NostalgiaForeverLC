# Loot Not Out Yet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a client that can't provide a raid's items (classic raids on Forever today), leave those items out of the catalogue and show a "not out yet" note, rechecking every session.

**Architecture:** A per-session "unavailable" set lives in `Core/Init.lua` next to the item-info wrappers. It is fed by `C_Item.DoesItemExistByID` (when the client has it) and by `GET_ITEM_INFO_RECEIVED(itemID, false)`. A pure `Engine.SplitAvailable` drops those IDs before `Engine.GroupBySlot`. `RaidData:GetLootRows` returns the rows plus a hidden count, and `UI/RaidView.lua` turns that count into a footer row or a whole-list note. The R8a preloader skips unavailable IDs.

**Tech Stack:** Lua 5.1 / luajit, WoW addon API, the `tests/run.lua` unit runner and the `tests/smoke.lua` mock.

**Spec:** `docs/superpowers/specs/2026-11-17-loot-not-out-yet-design.md` (diagnosis: `docs/superpowers/plans/2026-11-17-item-info-diagnosis.md`)

## Global Constraints

- `PRD.md` changes land before code (CLAUDE.md). Cite R8a / R8b / R9 in tests and commit bodies.
- Feature-detect every API, `(C_X and C_X.Fn)` style, looked up **at call time** for `C_Item.DoesItemExistByID` (the smoke test toggles it).
- Must work on interfaces `16001`, `11509` and `20506`. Without `DoesItemExistByID`, only the server's answer marks an item.
- The unavailable set is per session: never written to `NostalgiaForeverLCDB` / `NostalgiaForeverLCCharDB`.
- Only `success == false` marks an item; `success == true` clears the mark; `nil` changes nothing.
- Copy, exact:
  - footer row header: `Not out yet on this client` (rendered by the existing header style as `Not out yet on this client (N)`)
  - whole-list note: `This raid's loot isn't out on this client yet. It appears here on its own once it is.`
- Reserves already saved for unavailable items are untouched.
- Done = `bash scripts/check.sh` passes. In-game behaviour is "smoke-tested against the mock" only.
- Work on a branch (`fix/loot-not-out-yet`), not `main`.

## Review Focus

1. Server refuses an item, then a later answer succeeds (hotfix mid-session): the item must come back. → Task 3, `availability clears on a later success`.
2. Client without `C_Item.DoesItemExistByID` (Classic Era mock): nothing is hidden until the server refuses. → Task 3, `no DoesItemExistByID: only refusals count`.
3. `GET_ITEM_INFO_RECEIVED` with no success argument: must not hide the item. → Task 3, `nil success is ignored`.
4. A reserved item becomes unavailable: the player's wishlist must not change. → Task 4, `wishlist unchanged when its items go missing`.
5. Every item of a boss unavailable: the list must show the note, not the generic "learned as they drop" text. → Task 4, `whole boss shows the not-out note`.

---

### Task 1: PRD and README

**Files:**
- Modify: `PRD.md` (section 3.2, R8a and R9; add R8b after R8a)
- Modify: `README.md:71`

- [ ] **Step 1: Add R8b to `PRD.md` after R8a, exactly:**

```markdown
- **R8b** An item the game can't provide on this client (it says the item doesn't exist, or the server refuses the request) is left out of the loot list for the rest of the session. Every login checks again, so loot fills in on its own once it is released. A boss with some items left out ends its list with a **Not out yet on this client (N)** line. A boss with none available shows "This raid's loot isn't out on this client yet. It appears here on its own once it is." instead.
```

- [ ] **Step 2: Append to R8a:** ` An item the server refuses is not asked for again (R8b).`

- [ ] **Step 3: Append to R9:** ` Onyxia's Lair (Forever) shows the Classic Onyxia table until its own is known; while those items are not out on Forever it shows the R8b note.`

- [ ] **Step 4: Replace `README.md:71`** with: `- **Onyxia's Lair (Forever)** borrows the Classic Onyxia loot table, tagged "(classic)". Until Forever serves those items it shows a "not out yet" note; items that drop in the raid appear under "Seen in raid".` Also add one sentence after the **Classic raids** paragraph (line 74): `Until Forever serves the classic raid items, their catalogues show a "not out yet" note (R8b).`

- [ ] **Step 5: Run `bash scripts/check.sh`.** Expected: exit 0 (docs only).

- [ ] **Step 6: Commit**

```bash
git add PRD.md README.md
git commit -m "docs(prd): show raid loot the client can't provide as not out yet (R8b)"
```

---

### Task 2: `Engine.SplitAvailable`

**Files:**
- Modify: `Core/Engine.lua` (next to `Engine.GroupBySlot`, ~line 409)
- Test: `tests/engine_spec.lua` (in the `describe` that holds the GroupBySlot cases, ~line 297)

**Interfaces:**
- Produces: `Engine.SplitAvailable(items: {number}|nil, isUnavailable: fun(id): boolean|nil) -> available: {number}, hidden: number`. Keeps order. A nil `isUnavailable` hides nothing.

- [ ] **Step 1: Write the failing tests**

```lua
it("splits out unavailable items, keeping order (R8b)", function()
    local gone = { [2] = true, [4] = true }
    local avail, hidden = Engine.SplitAvailable({ 1, 2, 3, 4, 5 }, function(id) return gone[id] end)
    eq(table.concat(avail, " "), "1 3 5"); eq(hidden, 2)
end)
it("split: everything unavailable, empty and nil input", function()
    local avail, hidden = Engine.SplitAvailable({ 7, 8 }, function() return true end)
    eq(#avail, 0); eq(hidden, 2)
    avail, hidden = Engine.SplitAvailable(nil, function() return true end)
    eq(#avail, 0); eq(hidden, 0)
    avail, hidden = Engine.SplitAvailable({ 1 }, nil)
    eq(#avail, 1); eq(hidden, 0)
end)
```

- [ ] **Step 2: Run `luajit tests/run.lua`.** Expected: 2 FAIL, `attempt to call field 'SplitAvailable'`.

- [ ] **Step 3: Implement `Engine.SplitAvailable` in `Core/Engine.lua`** with a header comment citing R8b.

- [ ] **Step 4: Run `luajit tests/run.lua`.** Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Core/Engine.lua tests/engine_spec.lua
git commit -m "Add Engine.SplitAvailable for items the client can't provide (R8b)"
```

---

### Task 3: Availability state, loot rows and preload

**Files:**
- Modify: `Core/Init.lua` (after `Addon:GetItemEquipLoc`, and register the event after `Addon:RegisterEvent` is defined, ~line 276)
- Modify: `Core/RaidDataAPI.lua:160-162` (`GetLootRows`)
- Modify: `UI/Widgets.lua` (`isCached`/`retry`/`preloadStep`/`UI.PreloadItems`, ~lines 52-120)
- Test: `tests/smoke.lua` (mock near line 95; checks right after the R8a tooltip block, ~line 308)

**Interfaces:**
- Consumes: `Engine.SplitAvailable` (Task 2).
- Produces:
  - `Addon:IsItemUnavailable(itemID: number) -> boolean`: true when this session saw a refusal for it, or `C_Item.DoesItemExistByID` exists and returns false.
  - `GET_ITEM_INFO_RECEIVED(itemID, success)` handler in `Core/Init.lua`: `false` marks, `true` clears, `nil` ignored. The marks live in a file-local table. Init loads before UI, so this handler runs before the UI's refresh handler for the same event.
  - `RaidData:GetLootRows(boss) -> rows, hidden: number`: rows are `Engine.GroupBySlot` over the available items only.
  - The preloader never requests an ID for which `Addon:IsItemUnavailable` is true (first pass or retry).

- [ ] **Step 1: Extend the smoke mock.** In `G.C_Item` add `DoesItemExistByID = function(id) return not notOut[id] end`, with `local notOut = {}` declared beside `cache`.

- [ ] **Step 2: Write the failing smoke checks** after the R8a tooltip block (Lucifron selected, rows as in the existing `lootDump` check):

```lua
-- R8b: items the client can't provide are left out, per session.
do
    local function hiddenCount() local _, h = RDA:GetLootRows(RDA:GetBosses("MC")[1]); return h end
    event("GET_ITEM_INFO_RECEIVED", 17109, false); event("GET_ITEM_INFO_RECEIVED", 16863, false); runTimers()
    check(Addon:IsItemUnavailable(17109) and hiddenCount() == 2, "refused items are unavailable (R8b)")
    event("GET_ITEM_INFO_RECEIVED", 16805); runTimers()
    check(not Addon:IsItemUnavailable(16805), "nil success is ignored")
    local before = #itemRequests
    UI.PreloadItems({ 16863, 17109 }); runTimers(); runTimers()
    check(#itemRequests == before, "refused items are not requested again (R8a)")
    notOut[16800] = true
    check(Addon:IsItemUnavailable(16800) and hiddenCount() == 3, "unknown to the client = unavailable")
    local fn = G.C_Item.DoesItemExistByID; G.C_Item.DoesItemExistByID = nil
    check(not Addon:IsItemUnavailable(16800) and Addon:IsItemUnavailable(16863), "no DoesItemExistByID: only refusals count")
    G.C_Item.DoesItemExistByID = fn; notOut[16800] = nil
    event("GET_ITEM_INFO_RECEIVED", 17109, true); event("GET_ITEM_INFO_RECEIVED", 16863, true); runTimers()
    check(hiddenCount() == 0, "availability clears on a later success")
    event("PLAYER_LOGOUT")
    check(not G.NostalgiaForeverLCDB.unavailableItems and not G.NostalgiaForeverLCCharDB.unavailableItems, "unavailable set is not saved")
end
```

- [ ] **Step 3: Run `luajit tests/smoke.lua .`.** Expected: exit 1, `attempt to call method 'IsItemUnavailable'`.

- [ ] **Step 4: Implement** `Addon:IsItemUnavailable` and the event handler in `Core/Init.lua`, the two-value `RaidData:GetLootRows` using `Engine.SplitAvailable(boss and boss.items, function(id) return Addon:IsItemUnavailable(id) end)`, and the preload skip in `UI/Widgets.lua` (an unavailable ID counts as done: clear `preloadQueued[id]`, no request).

- [ ] **Step 5: Run `bash scripts/check.sh`.** Expected: exit 0, and the existing R8a checks (`every uncached MC item requested, then retried once`) still pass.

- [ ] **Step 6: Commit**

```bash
git add Core/Init.lua Core/RaidDataAPI.lua UI/Widgets.lua tests/smoke.lua
git commit -m "Track items the client can't provide and leave them out of loot rows (R8a, R8b)"
```

---

### Task 4: Catalogue notes

**Files:**
- Modify: `UI/RaidView.lua` (`EMPTY_TEXT` ~line 21; `refresh` ~lines 506-512)
- Test: `tests/smoke.lua` (extend the Task 3 block, before its final logout check)

**Interfaces:**
- Consumes: `RaidData:GetLootRows(boss) -> rows, hidden` and the smoke `notOut` table (Task 3).
- Produces: nothing new for other tasks.

- [ ] **Step 1: Write the failing smoke checks** (inside the Task 3 `do` block, right after the line `G.C_Item.DoesItemExistByID = fn; notOut[16800] = nil` and before the clearing events, so exactly 17109 and 16863 are unavailable):

```lua
    local wishBefore = table.concat(R:GetWishlist("MC").hard, ",") .. "|" .. table.concat(R:GetWishlist("MC").soft, ",")
    UI:RefreshShown(); runTimers()
    check(lootDump() == "Hands (1) 16805 Legs (1) 18875 Feet (4) 16800 16829 16837 16859 Not out yet on this client (2)",
        "partial boss ends with the not-out line: " .. lootDump())
    for _, id in ipairs(RDA:GetBosses("MC")[1].items) do notOut[id] = true end
    UI:RefreshShown(); runTimers()
    check(#liveRows(rf.itemList) == 0 and rf.empty:IsShown() and has(rf.empty._text, "isn't out on this client yet"),
        "whole boss shows the not-out note")
    for _, id in ipairs(RDA:GetBosses("MC")[1].items) do notOut[id] = nil end
    check(table.concat(R:GetWishlist("MC").hard, ",") .. "|" .. table.concat(R:GetWishlist("MC").soft, ",") == wishBefore,
        "wishlist unchanged when its items go missing")
```

After the clearing events, add: `UI:RefreshShown(); runTimers(); check(not rf.empty:IsShown() and not has(lootDump(), "Not out yet"), "rows come back once available")`.

- [ ] **Step 2: Run `luajit tests/smoke.lua .`.** Expected: exit 1, the `partial boss` check fails.

- [ ] **Step 3: Implement in `refresh`:** `local rows, hidden = RaidData:GetLootRows(boss)`. When `hidden > 0` and `#rows > 0`, append `{ header = "Not out yet on this client", count = hidden }` (drawn by the existing header branch of `updateItemRow`). Set `self.empty` text every refresh: `NOT_OUT_TEXT` (exact copy above, new local beside `EMPTY_TEXT`) when `#rows == 0 and hidden > 0`, else `EMPTY_TEXT`. Shown when `#rows == 0`.

- [ ] **Step 4: Run `bash scripts/check.sh`.** Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add UI/RaidView.lua tests/smoke.lua
git commit -m "Show a not-out-yet note for raid loot the client can't provide (R8b)"
```
