# I Don't Wanna LC — Product Requirements

Status: **active spec** (2026-11-17). This document is the source of truth for scope. Code, tests and the README follow it; when they disagree, this wins. Change the PRD first, then the code.

## 1. Purpose

A raid loot addon for WoW Forever that replaces loot council with **hard reserves (HR)** and **soft reserves (SR)**. Raiders choose their reserves **ahead of time, outside the raid**, so nothing has to be rushed at the instance portal. Once the raid starts, the addon turns those choices into roll lists. The raid leader always hands out the loot by hand; the addon never distributes items.

## 2. Roles

| Role | Who | Can do |
|---|---|---|
| Raider | Everyone with the addon | Browse raids, build HR/SR lists per raid, see everyone's active reserves, roll when eligible |
| Raid leader | The raid group leader | Everything a raider can, plus: approve reserve counts, lock/unlock reserves, see the roster inventory, whisper raiders, name the loot master |
| Loot master | The raid leader, or a raid assistant the leader names | Collect drops, run rolls, award, undo, disenchant/bank, tick items off as handed out |

The raid leader's client is the authority for reserves. The loot master's client is the authority for loot. By default they are the same player.

## 3. Requirements

Each requirement has an ID so plans, tests and commits can refer to it.

### 3.1 Raid list (home screen)

- **R1** Opening the addon (`/idwlc`, `/reserve`) shows the **Raids** tab: a vertical stack of wide, horizontal raid cards, one per raid available on this client.
- **R2** Each card shows: the raid name, a graphic unique to that raid, raid size, lockout progress as `X/N` bosses, how many times this character has cleared it, the date of the last boss kill, and how many HR/SR picks the player has saved for it.
- **R3** The raid the leader is currently running is marked **LIVE**, listed first, and shows the approved counts and lock state.
- **R4** Clicking a card opens that raid's catalogue (3.2). A Back button returns to the list.
- **R5** Stats are tracked per character from boss kills (`ENCOUNTER_END`) and the game's saved-instance data. A clear is counted once per lockout.

### 3.2 Raid catalogue

- **R6** The catalogue lists the raid's bosses. Clicking a boss shows the gear it drops.
- **R7** Loot is grouped by gear slot in a fixed order — Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Finger, Trinket, Weapon, Off-hand, Ranged — followed by **Misc / Quest** for everything else.
- **R8** Each item shows its icon and quality-coloured name. Hovering shows the standard item tooltip. Items behave like linked gear: shift-click links to chat, ctrl-click previews in the dressing room, shift-hover compares with equipped gear.
- **R9** Raids whose loot table is not known yet (new Forever raids) learn items as they drop; a link box lets players add any item by shift-clicking its link.

### 3.3 Reserve lists

- **R10** Every item row has **HR** and **SR** buttons that add it to (or remove it from) the player's hard or soft list for that raid.
- **R11** An item cannot be on both lists. Adding it to HR removes it from SR; adding to SR while it is on HR is refused.
- **R12** Each list holds at most **10** items.
- **R13** Lists are **per character, per raid**, and span the whole raid (not per boss). They can be edited at any time outside a locked live raid.
- **R14** Lists are **ranked**. Players reorder with up/down arrows. The top entries that fit the leader's approved counts become the player's **active** reserves; the rest are **standby** and move up when a slot opens or an item is won.
- **R15** Legendary-or-better items are restricted: they cannot be reserved and are skipped when active reserves are selected.
- **R16** Active reserves for the live raid are sent to the leader automatically. Everyone in the raid can see who has reserved what: while browsing the catalogue of the **live** raid, each item lists the other players who reserved it, split into **HR** names and **SR** names.

### 3.4 Settings

- **R17** The addon window has a **Settings** tab with sub-tabs. The **Master Loot** sub-tab sets the default number of hard and soft reserves per player.
- **R18** Defaults are **1 hard, 3 soft**. Valid values are **1–10** for each.
- **R19** Master Loot also holds the leader's other defaults: allow double soft reserve, consume reserve on award, announce channel, roll timeout.

### 3.5 Raid start: approval and lock

- **R20** The first time the raid leader enters a raid instance with a raid group, the addon prompts them to **approve** the HR and SR counts for that raid (pre-filled from the last counts approved for that raid, else the Master Loot defaults; adjustable 1–10 in the prompt).
- **R21** Approval starts the inventory: the raid and counts are sent silently to every client, each raider's active reserves are selected from their lists and sent back, and the rules are announced once in raid chat.
- **R22** The leader may dismiss the prompt and approve later from the Roster tab, and may start the inventory before zoning in by choosing the raid there.
- **R23** After approval raiders can still edit their lists until the leader **locks** reserves. The leader has a **Lock** button and is expected to press it before the first boss.
- **R24** The leader can **unlock** again. The leader **cannot** add, remove or change another player's reserves.
- **R25** Every approval, count change, lock and unlock is **announced in raid chat** for transparency.

### 3.6 Data sharing

- **R26** Clients exchange data over hidden addon messages only. Nothing is posted to chat except the announcements in R25, roll/award announcements, and whispers the leader sends on purpose (R30).
- **R27** Sending is rate-limited and pauses during boss encounters.
- **R28** Each client reports its addon version to the raid so the leader can tell who has the addon installed.

### 3.7 Roster tab (raid leader only)

- **R29** While in a raid group, the raid leader sees a **Roster** tab. Nobody else sees it. It lists every raid member with one of four states: **No addon**, **No picks**, **Incomplete** (fewer active reserves than the approved counts, shown as `HR a/b SR c/d`), or **Ready**.
- **R30** Each row that is not Ready has a **Whisper** button that sends that player a direct message telling them to install the addon or fill in their reserves. A **Whisper all** button does the same for everyone not Ready. Whispers to the same player are throttled.
- **R31** The Roster tab also holds the leader's live controls: approve/change counts, lock/unlock, refresh, export.

### 3.8 Loot window and rolls

- **R32** When loot drops, the leader's client resolves each item: restricted → leader decides; hard reserved → hard reservers only (single reserver wins without a roll); soft reserved → soft reservers roll; otherwise open roll. Roll lists come from the active reserves (R14, R21).
- **R33** A **loot window pops up for everyone in the raid** when loot drops (after the fight if it arrives mid-encounter). It lists every drop under the boss it came from, with who may roll for each item according to the hard and soft reserves.
- **R33a** The loot window must **never block play**. It can be closed at any time (X or Esc) while loot is still being handled, and once closed it stays closed for that batch of loot: further drops and rolls do not reopen it (a chat line points to `/idwlc loot`). It never opens during combat; it waits until the player is out of combat. With the window closed, a player is only interrupted by a small roll popup for items they can actually roll on. The window opens by itself again only after the current loot has all been handed out.
- **R34** The raid leader starts a roll per item. The window shows the rolls as they come in, for everyone: valid rolls ranked, ineligible or repeated rolls ignored, ties re-rolled. Eligible raiders get a Roll button.
- **R35** The raid leader hands the item out **by hand** and presses Award (the suggested winner, or anyone for restricted items and overrides). Only the leader has roll and award controls. The award is **announced in raid chat**. Winning an item consumes that reserve and removes it from the winner's list.
- **R36** Loot tracking runs only in a raid group inside a raid instance.

### 3.9 Loot ledger

- **R37** Every raid run with the addon is recorded in a **loot ledger**, automatically. A run is one raid on one night (same raid, no gap longer than 12 hours).
- **R38** For each drop the ledger stores the item, the boss, the time, who the leader awarded it to, how it was decided (hard reserve, soft reserve, open roll, leader's call) and the rolls. Drops that were never awarded are kept as "not awarded"; a drop the leader removes as a mistake is taken out.
- **R39** The ledger is saved account wide on every client in the raid (leader and raiders each keep their own copy) and survives clearing the loot window. Up to 200 runs are kept.
- **R40** A **Ledger** tab lists past runs, newest first; selecting one shows its drops per boss and who got what, with the rolls on hover. A run can be exported as text or deleted.
- **R41** The ledger exists first of all to capture data. Features built on it (attendance, loot history per player, fairness stats) are future work.

### 3.10 Guild ledger sync and backups

- **R42** Guild mates can fill gaps in their ledger (raids they missed, drops their client never saw) by syncing with the guild. Sync is a **manual poll**: it only runs when the player presses **Sync with guild** on the Ledger tab. Nothing syncs in the background.
- **R43** **Only a run's raid leader is its source.** A client only hands out runs it led, and a run is only accepted when it comes from the player recorded as its raid leader. Other raiders' copies are never used.
- **R44** **Only runs led by a member of the guild count.** Each run is stamped with its leader's guild when it is recorded. A leader only offers runs led for the guild they are in, and a receiver only accepts runs stamped with their own guild from a sender on their guild roster. Different officers leading in different weeks all contribute to the same guild's history.
- **R45** Every run carries a shared ID given by the leader's client and sent with each drop, so the same raid is recognised on every client.
- **R46** Sync **never overwrites** what a client recorded itself. It adds missing runs, adds missing drops to a run, and fills in a missing winner. Synced runs are labelled with who they came from.
- **R47** Sync travels over hidden addon messages (guild channel for the poll, addon whispers for the data), in chunks with a checksum. A transfer that is incomplete or damaged is rejected. Polling is rate limited.
- **R48** **Backups.** A copy of the ledger is taken before every sync, before every restore, on demand, and when damaged saved data is repaired on load. The last 5 are kept, account wide, and any of them can be restored from the Ledger tab. Unreadable records are removed on load so a damaged file cannot break the addon.

### 3.11 Incomplete data and missing addon

- **R49** **Short lists.** When the approved counts allow more reserves than a player's lists can fill, that player is told: in chat and as an on-screen notice when the rules arrive or change and when they zone into the raid, in the rules banner, in the catalogue header ("Add 2 SR more") and on the live raid card. Once reserves are locked they are told once what went unused.
- **R50** **Locking with players not ready.** If the leader locks while anyone has no addon, no picks or incomplete picks, the addon states how many of each and asks for confirmation. Locking is still allowed.
- **R51** **Players without the addon** show as "No addon" on the roster and can be whispered to install it. They have no reserves, can still `/roll` on unreserved items (rolls are read from chat), and can be awarded any item by the leader.
- **R52** **Joining after the lock.** A player the leader has no reserves for can still send a first set; nobody can change a set while locked.
- **R53** **Leaving the raid.** A player's reserves are dropped when they leave, so nothing is held for someone who is gone.
- **R54** **Awards go to raid members only.** A typed winner must match someone in the raid (case-insensitive); otherwise nothing is awarded, announced or written to the ledger.
- **R55** **Version mismatch.** A raid member whose addon version differs from the leader's is flagged on the roster.
- **R56** **Unknown items.** An item whose quality the client doesn't know yet can be listed; the legendary restriction is applied again when it drops. Restricted or duplicate entries on a list are marked and skipped, and the next entry moves up.

### 3.12 Loot master tools

Policy defaults below are settings in **Settings > Master Loot** unless stated otherwise. They take effect the next time counts are approved.

- **R57 Loot master.** The raid leader can put a raid assistant in charge of loot from the Roster tab (and take it back). The change is announced in raid chat. Loot messages are only accepted from the current loot master. If that player leaves or loses assist, loot falls back to the raid leader. The leader remains the authority for reserves throughout.
- **R58 Fallback roll.** When no reserver takes a reserved item (passed, offline, didn't roll), the loot master can **open it to everyone** with one click. It is then rolled, announced and recorded as an unreserved item.
- **R59 Main spec / off spec.** On unreserved items `/roll 100` is a main-spec roll and `/roll 99` an off-spec roll; off spec only wins when nobody rolled main spec. Default **on**. Reserved items take `/roll 100` only. Players get separate Main spec / Off spec buttons.
- **R60 Plus-ones.** On unreserved items, a player who has won fewer unreserved items this run beats a higher roll (within main spec or within off spec). Default **off**. Only main-spec wins of unreserved items count; reserved wins, off-spec wins, disenchants and bank items do not.
- **R61 Undo.** The loot master can undo any award. The item is pending again, the winner's reserve returns, the item returns to the winner's own list in its old position, the ledger entry is cleared, and the undo is announced in raid chat.
- **R62 Hand-out tracking.** Awarded items stay listed as "to hand out" until they are traded. A completed trade with the winner that contained the item ticks it off automatically; the loot master can also tick it by hand. "Clear finished" keeps items not yet handed out. The ledger records whether an item was handed over.
- **R63 Disenchant / bank.** The loot master can send an unwanted item to be disenchanted or to the guild bank. It goes to the player named for that in the settings if they are in the raid, otherwise it stays with the loot master. It uses nobody's reserve and is recorded in the ledger as disenchanted or banked, not as a win.
- **R64 Soft reserve bonus.** Optionally, a soft reserve roll gets a bonus for every earlier run of the same raid in which that player soft reserved the item and did not get it. The streak counts back from the most recent run and ends at the first run where they won it or did not reserve it. Per-run amount 0-50 (default **0 = off**), cap 0-100 (default 30). The bonus is announced with the roll, shown next to each roll, and computed from the loot master's ledger.
- **R65 Import for players without the addon.** The raid leader can type or paste reserves ("Name, item, HR|SR" lines or a softres.it CSV) for raid members who do **not** have the addon. A player whose client has reported in or sent its own reserves is never touched. Imports are trimmed to the approved counts, marked on the roster, announced in raid chat, and replaced by the player's own picks if they install the addon. This is the only way the leader enters reserves for anyone else (see R24).
- **R66 Lists as text.** A player can export their lists for a raid as one line of text and import such a line (another character, a friend). Import replaces the lists for the raid named in the text and leaves out legendaries, armor the class can't wear and anything past 10 per list.
- **R67 Tooltips.** Item tooltips anywhere in the game show where the item is on the player's own lists and, in the live raid, who has it hard and soft reserved. Can be switched off in Settings > General.
- **R68 Class check.** A player cannot reserve armor their class can never wear (cloth < leather < mail < plate, shields). Weapons, trinkets and tokens are not checked.
- **R70 Resilience.** The loot master's list (drops still to roll, items still to hand out) survives a reload; a roll that was running is cancelled for everyone. When the raid leader comes back from a reload or disconnect, an assistant loot master repeats its awards so the leader's reserves catch up, and a repeated award is only ever recorded once. Raid messages (rules, drops, rolls, awards) are only accepted over the raid channel, never as whispers. Members are told when a roll closes.
- **R69 Reserve change log.** After approval, every change to a player's active reserves is logged on the raid leader's client with the time and how many bosses had died. The Roster tab shows the log and flags changes made after the first kill. The log is attached to the run in the leader's ledger.

## 4. Out of scope (for now)

- More than one loot master at a time; assistants approving counts or locking.
- The leader editing reserves of players who have the addon.
- Weapon and trinket usability checks; bonus or plus-one history shared between clients.
- Anything built on top of the ledger data (R41).
- Automatic or background ledger sync; syncing reserve lists; syncing with players outside the guild.
- Bespoke raid artwork files. Cards use in-game icons and per-raid colours until art is added (`art` field in `Data/RaidMeta.lua`).

## 5. Constraints

- Lua 5.1, WoW addon API only, no libraries. Must load on interface `16001` (WoW Forever) and `11509` (Classic Era, for testing).
- `Core/Engine.lua` stays free of WoW API calls and is unit tested with `luajit tests/run.lua`.
- UI is covered by `luajit tests/smoke.lua .` against a mock WoW API. Both must pass in CI.
- Addon messages are under 255 bytes, `^`-separated, prefix `IDWLC`.

## 6. Open questions

- WoW Forever's loot method is unconfirmed (see README, Known gaps).
- Forever raid loot tables, boss lists and instance IDs are unpublished; cards for those raids show progress only once the game reports a lockout.
- Nothing here has been verified in the live game client yet.
