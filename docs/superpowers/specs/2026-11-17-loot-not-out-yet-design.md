# Design: "loot not out yet" for raids the client can't show

Short design (small change). Diagnosis: `docs/superpowers/plans/2026-11-17-item-info-diagnosis.md`.

## Why

On the Forever client every classic raid catalogue shows `item:16800`-style
rows with no tooltip. AtlasLoot Classic Forever's raid pages are blank too, so
Forever isn't serving the classic raid items yet (first raid tier unlocks
Dec 9, 2026). Players should see an honest note, not broken rows. When the
loot arrives, the catalogue should fill in without an addon update.

## Goals / non-goals

- Goal: an item the game says it can't provide is not drawn as a row. A boss
  with no available items shows a note in the loot list.
- Goal: detection is live, so the same build shows real loot once Forever
  releases it.
- Non-goal: hiding raids, or changing the raid cards (R1-R5 unchanged).
- Non-goal: changing reserves already saved for such items.
- Anti-goal: calling loot "not out yet" when it is only slow to load.

## Approaches (user picked A)

- **A. Ask the game per item (picked).** Unavailable = `C_Item.DoesItemExistByID(id)`
  returns false, or the server answers `GET_ITEM_INFO_RECEIVED(id, false)`.
  Live, works whichever way Forever holds the items back.
- B. Hand-tag classic raids "not out on Forever" in the data. Stale the moment
  the loot ships, until a release.
- C. Treat "still uncached after the retry" as unavailable. A slow server would
  falsely show the note.

## Behaviour

- Each item ID is in one of three states: **available**, **pending** (asked,
  no answer yet: drawn as today) or **unavailable**. Unavailable is held for
  the session only (not saved), so every login checks again.
- Loot list (R7): unavailable items are left out of their slot groups. If
  some items of a boss are left out, a last line says
  `N items not out yet on this client`. If none are left, the list shows
  instead of the usual empty text:
  `This raid's loot isn't out on this client yet. It appears here on its own once it is.`
  The link box (R9) works as today.
- Boss list (R6): unchanged; boss names come from our data.
- R8a preload: skips IDs already unavailable and does not retry an ID the
  server refused.
- `C_Item.DoesItemExistByID` is feature-detected (the `(C_X and C_X.Fn)`
  pattern); without it, only the server's answer marks an item unavailable.

## Calls I made (check these)

- **Forever Onyxia keeps borrowing the classic Onyxia table.** Earlier I said
  the borrow would go. With A it is harmless: it shows the note until those
  items exist, and dropping it would list Onyxia twice on Forever (the Forever
  card plus the classic one). Items that drop in the Forever raid still appear
  under "Seen in raid" (R9).
- The partial-boss count line is my addition; it tells players the list
  is incomplete instead of silently short.
- State lives in a small module beside `UI.ItemInfo` in `UI/Widgets.lua`, with
  the filter applied in `RaidData:GetLootRows` so the smoke test can check it.

## Changes

- `PRD.md` first: add **R8b** (the behaviour above); amend R8a (no retry for
  refused items); note the Onyxia borrow showing the note under R9.
- Code: availability state + `GET_ITEM_INFO_RECEIVED` success flag
  (`UI/Widgets.lua`), filter in `Core/RaidDataAPI.lua`, note text and count
  line in `UI/RaidView.lua`.
- Tests: smoke mock gains `C_Item.DoesItemExistByID` and a failing
  `GET_ITEM_INFO_RECEIVED`; checks for whole-boss note, partial count line,
  no retry of refused IDs, and an item flipping to available on a new session.
- README: replace "shows the Classic Onyxia loot for now" with the note behaviour.

## Left to the builder

- Exact wording and colour of the two notes (keep them short and grey like
  `EMPTY_TEXT`).
- Whether the count line is a row in the scroll list or a label under it.

Done = `scripts/check.sh` passes; in-game behaviour is "smoke-tested against
the mock" until the user checks it on Forever.
