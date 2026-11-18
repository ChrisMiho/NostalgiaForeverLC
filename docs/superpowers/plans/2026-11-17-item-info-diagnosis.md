# Diagnosis plan: raid items show as `item:NNNNN` with no tooltip

Status: investigation, nothing fixed yet. Requirements involved: R6, R8, R8a, R9.

## Symptom

On the WoW Forever client (build 1.60.1.70959, installed release v0.4.0-alpha.2,
identical code to `main` at `0935f03`), every catalogue row shows the fallback
text `item:<id>` instead of a name, and hovering a row shows no item tooltip.

## What was ruled out (from code and the install, not in game)

- **Stale install.** The AddOns folder copy matches `0935f03` apart from packager
  output (`CHANGELOG.md`, `.toc` keywords). The R8a batching code is running.
- **Wrong data shape.** `Data/Raids.lua` holds plain numeric IDs (16800, ...);
  `RaidData:GetBosses` passes them through unchanged; `UI.ItemInfo`,
  `itemSetItem` and `itemOnEnter` receive numbers, not strings or tables.
- **Event dispatch.** `Addon:RegisterEvent` keeps a list per event, so the two
  `GET_ITEM_INFO_RECEIVED` handlers (`Core/Loot.lua`, `UI/Widgets.lua`) both run.
- **API choice.** AtlasLoot Classic Forever (installed alongside) uses the same
  calls (`C_Item.GetItemInfo`, `GameTooltip:SetHyperlink` / `SetItemByID`) on the
  same classic IDs.
- **Server throttling** (the R8a hypothesis) is now unlikely to be the whole
  story: batching and the retry shipped and nothing changed.

## Leading hypothesis

> The Forever client or server does not provide the Classic raid items
> (Molten Core, BWL, Onyxia, ...), so `GetItemInfo` never returns a name and the
> tooltip has nothing to show.

Evidence for it:
- Forever's own items are a new ID range: AtlasLoot's `forever.lua` lists
  dungeon loot at 270227, 271096, ... None of the IDs we display are in it.
- Our row fallback (`item:<id>`, question-mark icon) plus an empty tooltip is
  what the game does for an item ID it does not know.
- `Data/Forever.lua` says the first Forever raid tier unlocks Dec 9, 2026. If
  classic raid items exist but are held back (encrypted or not served until
  the tier is live), the server answers item requests with `success = false`.

Evidence against it: AtlasLoot Classic Forever ships the classic MC tables for
this client. Either they also show blank there, or the items do exist. The
in-game checks below settle this.

## Findings so far (2026-11-17)

- ForeverDungeonJournal shows classic *dungeon* loot by classic IDs (5191,
  16731, ...), so the client does know pre-raid classic items.
- AtlasLoot Classic Forever's *raid* pages are blank in game too (the user checked),
  using the same IDs and APIs as us. So our display code isn't the cause:
  classic raid items are not served on Forever yet. Still open: whether they are
  missing from the client (`DoesItemExistByID` false) or present but refused by
  the server (`GET_ITEM_INFO_RECEIVED` success false). Check 1 and check 2 below
  decide that, and the answer changes how the addon detects it.

## Phase 1: gather evidence in game (no code changes)

Run each line in the chat box on the Forever client and write down the output.
IDs: 16800 Arcanist Boots (MC), 19019 Thunderfury (MC), 270227 Ephemeral
Choker (a Forever dungeon item, should work), 6948 Hearthstone (control).

1. Does the client know the item locally (no server needed)?
   ```
   /run for _,i in ipairs({16800,19019,270227,6948}) do print(i,C_Item.DoesItemExistByID(i),(select(5,C_Item.GetItemInfoInstant(i))),(C_Item.GetItemInfo(i))) end
   ```
   Prints: id, exists?, icon file ID, name (nil while uncached; run twice).

2. What does the server answer?
   ```
   /run local f=CreateFrame("Frame")f:RegisterEvent("GET_ITEM_INFO_RECEIVED")f:SetScript("OnEvent",function(_,_,i,ok)print("recv",i,ok)end)for _,i in ipairs({16800,19019,270227})do C_Item.RequestLoadItemDataByID(i)end
   ```
   Prints `recv <id> true|false` per item.

3. Raw tooltip, outside the addon:
   ```
   /run GameTooltip:SetOwner(UIParent,"ANCHOR_CURSOR")GameTooltip:SetItemByID(16800)GameTooltip:Show()
   ```

4. Open AtlasLoot, go to Molten Core > Lucifron. Do names and tooltips show?

5. In our addon, open Onyxia's Lair (Forever), shift-click an item from your
   bags into the link box. Does that row show its name and tooltip?

## Phase 2: decide from the results

| Result | Meaning | Next step |
|---|---|---|
| 16800 `exists=false` / no icon; 270227 fine | Classic raid items are not in the Forever client | Scope change (below) |
| 16800 exists locally but `recv 16800 false`; 270227 `true` | Items exist but the server will not serve them yet | Scope change, plus treat `success=false` as "unavailable" |
| All succeed, AtlasLoot shows names, our rows still blank | Bug in our display path | Add `/nflc debug item <id>` that prints each step of `UI.ItemInfo` and the tooltip call, then trace it |
| Step 5 also blank, or 270227 / 6948 fail too | Client cache or environment | Close the game, delete `_forever_\Cache`, retest before touching code |

### If it is a scope change (likely)

PRD first, per `CLAUDE.md`:
1. Amend PRD: Classic raid tables are listed only on clients that have those
   items (Classic Era / TBC). On Forever, the catalogue lists Forever raids only;
   their loot comes from R9 learning and the link box until real tables exist.
   Decide whether F_ONY keeps `lootFrom = "ONY"` (it cannot, if those items
   are missing).
2. Detect availability at runtime instead of by interface number, e.g. hide a
   raid whose items fail `C_Item.DoesItemExistByID`, so a future Forever patch
   that adds them lights the raids up again without a code change.
3. Handle `GET_ITEM_INFO_RECEIVED` with `success == false`: stop retrying that
   ID (R8a currently asks twice and ignores the flag) and show an
   "unavailable on this client" state rather than `item:<id>`.
4. Tests: data/engine specs for the availability filter; smoke mock gains
   `C_Item.DoesItemExistByID` and a failing `GET_ITEM_INFO_RECEIVED`.
5. Say "smoke-tested against the mock" only; the user verifies in game.

## Open questions

- Will Forever add the classic raids (or Forever versions with new IDs) on
  Dec 9? If new IDs, `Data/Forever.lua` gets real `bosses` tables via the
  `add-forever-raid` skill.
