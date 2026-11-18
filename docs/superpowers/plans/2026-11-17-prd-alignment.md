# PRD Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the addon into one tabbed window (Raids → catalogue, Roster, Settings) with leader approval, roster inventory and raid stats, as specified in the PRD.

**Architecture:** Pure rules stay in `Core/Engine.lua` (unit tested). New WoW-facing modules `Core/Stats.lua` and `Core/Roster.lua` sit beside `Core/Reserves.lua`. The UI becomes a single `Main` window hosting panels; the old Reserve window becomes the raid catalogue panel and the old Leader window is replaced by the Roster panel.

**Tech Stack:** Lua 5.1 (LuaJIT for tests), WoW addon API, no libraries.

**Spec:** [PRD.md](../../../PRD.md)

## Global Constraints

- Interface `16001` and `11509` must both load; only API present on both, feature-detected otherwise.
- `Core/Engine.lua` has no WoW API calls.
- Reserve counts: default 1 hard / 3 soft, valid 1–10. List cap 10 per kind.
- Addon messages < 255 bytes, `^`-separated, prefix `IDWLC`.
- Leader can lock/unlock, never edit another player's reserves.
- `luajit tests/run.lua` and `luajit tests/smoke.lua .` pass with `ERRORS 0` after every task.
- The smoke-test mock returns a function for any unknown frame field, so never keep boolean state in frame fields that may be unset; use locals.

## Review Focus

1. Leader reloads UI mid-raid: approval and lock must survive (`db.session.approved`), no second prompt. — Task 3 test.
2. A raider with fewer list items than the approved counts must show **Incomplete**, not Ready. — Task 1 test.
3. Items whose info is not cached must still land in a slot group (use instant item info) and not crash grouping when equipLoc is nil. — Task 1 test.
4. Leaving the raid group must clear the live session so last week's raid is not shown as LIVE. — Task 3 test.
5. Non-leaders must never see the Roster tab, including after losing leadership with the tab open. — Task 5 test.

---

### Task 1: Engine rules

**Files:** Modify `Core/Engine.lua`; Test `tests/engine_spec.lua`

**Interfaces — Produces:**
- `Engine.DEFAULT_SETTINGS.softReserves == 3`; `Engine.MIN_RESERVES = 1`; `Engine.MAX_RESERVES = 10`
- `Engine.ClampCount(n, default) -> integer` in 1..10 (non-number → default)
- `Engine.SLOT_ORDER` (list of group names, last is `Engine.MISC_SLOT = "Misc / Quest"`); `Engine.SlotGroup(equipLoc) -> groupName`
- `Engine.GroupBySlot(items, equipLocOf) -> rows` where a row is `{ header = name, count = n }` or `{ itemID = id }`, groups in `SLOT_ORDER`, items keep input order
- `Engine.STATUS = { NOADDON, EMPTY, PARTIAL, READY }`; `Engine.MemberStatus(hasAddon, reserve, settings) -> status`
- `Engine.NewStats() -> { clears = 0, kills = 0, killed = {} }`; `Engine.RecordKill(stats, boss, total, now)`; `Engine.MarkCleared(stats, now, resetAt)`; `Engine.Progress(stats, now) -> killedCount`
- `Session.approved` (boolean, default false)

- [ ] Write failing tests: ClampCount (0→1, 11→10, "x"→default, 3.7→3); SlotGroup (`INVTYPE_ROBE`→Chest, `INVTYPE_2HWEAPON`→Weapon, `INVTYPE_HOLDABLE`→Off-hand, `""`/nil→Misc / Quest); GroupBySlot order and header counts with a nil equipLoc; MemberStatus four states incl. reserve with 1/3 soft → PARTIAL and reserve present without hasAddon → not NOADDON; RecordKill counts a boss once, clear counted once when killed == total, lockout expiry (resetAt passed, or 7 days since last kill when resetAt unknown) empties progress; MarkCleared idempotent per lockout.
- [ ] Run `luajit tests/run.lua` — new tests fail.
- [ ] Implement.
- [ ] Run `luajit tests/run.lua` — all pass.

### Task 2: Raid metadata, stats and item grouping data

**Files:** Create `Data/RaidMeta.lua`, `Core/Stats.lua`; Modify `Core/RaidDataAPI.lua`, `Core/Init.lua`, `IDontWannaLC.toc`; Test `tests/data_spec.lua`

**Interfaces — Produces:**
- `ns.RaidData.meta[raidKey] = { artItem = itemID | nil, icon = texturePath, color = { r, g, b }, art = texturePath | nil }` for every raid key
- `RaidDataAPI:GetMeta(key)`, `:GetBossCount(key)` (excludes "Trash", "… Shared loot", "Seen in raid"), `:KeyForName(instanceName)`, `:GetLootRows(boss)` (GroupBySlot using `Addon:GetItemEquipLoc`)
- `Addon:GetItemEquipLoc(itemID)` (`C_Item.GetItemInfoInstant` / `GetItemInfoInstant`, falling back to `GetItemInfo`)
- `charDB.raidStats[raidKey]`; `ns.Stats:Get(key) -> { clears, killed, total, lastKill }`; records on `ENCOUNTER_END` success in a raid instance, reconciles on `UPDATE_INSTANCE_INFO`

- [ ] Data test: every classic and Forever raid key has a meta entry with `icon` and `color`.
- [ ] Implement; add files to the `.toc` (`Data\RaidMeta.lua` after `Data\Forever.lua`, `Core\Stats.lua` after `Core\RaidDataAPI.lua`).
- [ ] Run both test commands.

### Task 3: Approval, lock and session lifecycle

**Files:** Modify `Core/Reserves.lua`, `Core/Comm.lua`, `Core/Loot.lua`, `Core/Init.lua`, `Core/Slash.lua`; Test `tests/smoke.lua`

**Interfaces — Produces:**
- `Reserves:GetProposal(raidKey) -> hard, soft` (last approved for the raid, else Master Loot defaults)
- `Reserves:LeaderApprove(raidKey, hard, soft) -> bool` — clamps, sets raid + counts + `session.approved`, saves the per-raid preset, broadcasts CFG, announces, pings
- `Reserves:RequestApproval(raidKey)` fires `APPROVAL_NEEDED(raidKey)`; `Reserves:CheckApproval()` fires it once per raid key when the leader is in a raid instance without an approved session
- `Reserves:LeaderSetLocked(bool)` (requires approved session); `Reserves:ResetSession()`
- Removed: `LeaderSetRaid`, `LeaderSetCounts`, `LeaderSetOption`, `LeaderRemove`
- Comm: `PING` (leader → raid), `VER^version` (anyone → raid); `Comm.versions[name]`; `Comm:SendPing()`; fires `ROSTER_CHANGED`. Members set `session.approved = true` on CFG. The leader answers HELLO only when approved.

- [ ] Smoke checks: `CheckApproval` in MC fires `APPROVAL_NEEDED("MC")` once; `LeaderApprove("MC", 0, 99)` yields 1/10; the session persists `approved` through `PLAYER_LOGOUT`; leaving the raid (`IsInRaid` false + `GROUP_ROSTER_UPDATE`) clears `raidKey`/`approved`; lock and unlock each put a line in RAID chat; `VER` from Bob sets `Comm.versions.Bob`.
- [ ] Implement.
- [ ] Run both test commands.

### Task 4: Roster inventory

**Files:** Create `Core/Roster.lua`; Modify `IDontWannaLC.toc`; Test `tests/smoke.lua`

**Interfaces — Consumes:** `Engine.MemberStatus`, `Comm.versions`. **Produces:**
- `Roster:GetRows() -> { { name, fullName, class, online, version, status, hard, soft } }`, worst status first then name
- `Roster:Summary() -> ready, total`
- `Roster:WhisperText(row) -> string`; `Roster:Whisper(row) -> bool` (30 s per-player throttle, leader only); `Roster:WhisperAll() -> count`

- [ ] Smoke checks: with Bob reporting a version and no picks and Ann silent → Bob `empty`, Ann `noaddon`; whisper to Ann goes to `WHISPER` with her full name and mentions installing; a second whisper inside 30 s is refused.
- [ ] Implement; add to `.toc` after `Core\Reserves.lua`.
- [ ] Run both test commands.

### Task 5: Main window, raid cards, catalogue, roster, settings, approval prompt

**Files:** Create `UI/MainFrame.lua`, `UI/RaidList.lua`, `UI/RaidView.lua` (from `UI/ReserveFrame.lua`), `UI/RosterPanel.lua`, `UI/SettingsPanel.lua`, `UI/ApprovePopup.lua`; Delete `UI/ReserveFrame.lua`, `UI/LeaderFrame.lua`; Modify `UI/Widgets.lua`, `Core/Slash.lua`, `IDontWannaLC.toc`; Test `tests/smoke.lua`

**Interfaces — Produces:**
- `UI:RegisterPanel(key, { title, create = fn(parent) -> frame, visible = fn() -> bool | nil })`; `UI:ShowMain(tabKey)`, `UI:ToggleMain()`, `UI:OpenRaid(raidKey)`, `UI:ShowRaidList()`
- Panels: `raids` (list or catalogue), `roster` (visible only when `IsInRaid() and Addon:IsLeader()`), `settings`
- `UI:ShowApproval(raidKey)`
- `UI:CreateScrollList(parent, rowHeight, createRow, updateRow, heightOf)` — optional per-row height
- Item buttons call `HandleModifiedItemClick(link)` when available; tooltip shows compare on shift
- Test handles: `UI.raidList`, `UI.raidView`, `UI.rosterPanel`, `UI.settingsPanel`, `UI.approvePopup`

- [ ] Rewrite the smoke test for the new flow: open → cards (LIVE first, stats text) → click card → boss → slot headers → HR/SR adds with the HR/SR exclusion and 10 cap → Back; settings Master Loot clamps at 1 and 10 and defaults to 1/3; approval popup approves; roster tab hidden for non-leaders and after losing leadership; whisper button; lock button; member CFG banner still works.
- [ ] Implement.
- [ ] Run both test commands; run the CI parse check over `Core/*.lua Data/*.lua UI/*.lua`.

### Task 6: Docs

**Files:** Modify `README.md`, `IDontWannaLC.toc` (version `0.3.0`), `.github/workflows/test.yml` only if file globs change

- [ ] README matches the PRD: flow, commands, settings, layout, known gaps.
- [ ] Run both test commands one last time.
