# I Don't Wanna LC

A **raid loot addon for WoW Forever** that runs your raid on **hard and soft reserves** instead of loot council. Everyone in the raid installs it. Players pick their reserves ahead of time, outside the raid. When something drops, the addon works out who is allowed to roll. **The raid leader still hands out every item themselves.** The addon never distributes loot.

> Status: **draft (v0.3.0)**. Not tested in game yet. See [Known gaps](#known-gaps--next-steps).
>
> Scope and requirements live in [PRD.md](PRD.md). Change the PRD first, then the code.

## How it works

### Everyone: pick your reserves before the raid

1. `/idwlc` opens the **Raids** tab: one card per raid with its size, your lockout progress (`X/N` bosses), how often you've cleared it, your last kill and how many picks you've saved.
2. Click a raid to open its **catalogue**. Bosses are on the left; click one to see its loot **grouped by gear slot**, with everything else under *Misc / Quest*. Items behave like any linked item: hover for the tooltip, shift-click to link, ctrl-click to try it on.
3. Click **HR** or **SR** on an item to put it on your **hard** or **soft** list for that raid. An item can't be on both. Each list holds up to **10** items and is **ranked**; reorder with the arrows at the bottom.
4. Lists are saved per character, per raid. Do this for every raid you plan to run. **Export / Import** copies a raid's lists as one line of text (another character, a friend).
5. You can't reserve armor your class can't wear, and item tooltips everywhere show where an item is on your lists and who has it reserved in the live raid.

When you join a raid, **your top picks that fit the leader's counts become your active reserves automatically**. With 1 HR and 3 SR, your #1 hard pick and your #1–#3 soft picks are sent; the rest wait on **standby** and move up if a slot opens or you win something. Legendary-or-better items can't be reserved.

### Raid leader: approve, check the roster, lock

1. Set your defaults once under **Settings → Master Loot**: hard and soft reserves per player (1–10 each, default **1 hard / 3 soft**) and the other loot rules.
2. The first time you enter a raid as raid leader, the addon asks you to **approve the counts** for it. Approving sends the rules to every client silently, collects everyone's active reserves, and announces the rules once in raid chat. You can dismiss the prompt and approve later, or start early with **Roster → Choose raid**.
3. The **Roster** tab (only the raid leader sees it) lists every raid member as **No addon**, **No picks**, **Incomplete** or **Ready**. Each player who isn't ready has a **Whisper** button that sends them a reminder; **Whisper all** does the lot.
4. For raiders **without the addon**, use **Roster > Import reserves** to type or paste their picks (`Name, item, HR|SR` lines or a softres.it CSV). It never touches anyone who has the addon. **Roster > Changes** lists every reserve change since approval and flags ones made after a boss died.
5. If someone's lists are too short to use every reserve you allowed, **they are told automatically** (chat, on-screen notice, and a red "Add 2 SR more" in their window), and they show as *Incomplete* on your roster.
6. Press **Lock reserves** before the first boss. If anyone isn't ready, the addon tells you who and asks first. You can **unlock** again. Every approval, count change, lock and unlock is announced in raid chat. You can't change anyone else's picks.

### When loot drops

| Drop | What happens |
|---|---|
| **Legendary or higher** | **Restricted.** No reserves, no roll. The raid leader decides. |
| **Hard reserved** | Hard beats soft. One hard reserver gets it with no roll; several roll among themselves. |
| **Soft reserved** | Only the soft reservers may `/roll`. |
| **Not reserved** | Open `/roll` for everyone. |

The leader's client picks up each drop, and a **loot window pops up for everyone** listing the drops under the boss they came from, with who may roll for each. The leader clicks **Start roll**; eligible players get a **Roll** button, and everyone sees the rolls come in. The addon tracks valid `/roll 100` results, re-rolls ties and suggests a winner. The leader clicks **Award**, which announces the winner in raid chat, then loots or trades the item by hand. Winning an item uses up that reserve. Loot tracking only runs in a raid group inside a raid instance.

**Loot master tools** (the raid leader, or an assistant named on the Roster tab):

| | |
|---|---|
| **Open to all** | No reserver took a reserved item: put it up for everyone |
| **Main spec / off spec** | On unreserved items `/roll 100` beats `/roll 99`. On by default |
| **Plus-ones** | On unreserved items, fewer items won this run beats a higher roll. Off by default |
| **Soft reserve bonus** | +N to a soft reserve roll per earlier run you reserved the item and lost. Off by default |
| **Disenchant / Bank** | Nobody wants it: recorded as such, uses nobody's reserve |
| **Undo** | Take an award back: reserve, lists and ledger are restored, and it's announced |
| **Handed out** | Awarded items stay listed until traded; trades are noticed automatically |

The loot window never gets in the way: close it any time (X or Esc) and it **stays closed until that loot is done**, even as more drops and rolls come in. It never opens during combat. While it's closed you only get a small roll popup for items you can actually roll on; `/idwlc loot` brings the window back.

### Loot ledger

Every drop and every award is written to the **loot ledger** automatically: the raid, the date, the boss, the item, who got it, how it was decided and the rolls. Each client in the raid keeps its own copy, account wide. The **Ledger** tab lists past raids (newest first) and what happened in each; a run can be exported as text. It is there to capture the data first; features built on it come later.

**Sync with guild** (Ledger tab) fills gaps for people who missed a raid. It is a manual poll: press the button and your client quietly asks guild mates who led raids for their record of those runs. Only a run's own raid leader is accepted as its source, only for runs led by a member of your guild, and nothing you recorded yourself is overwritten. The leader has to be online when you press it.

**Backups** (Ledger tab) keeps the last 5 copies of the ledger. One is taken before every sync and restore, and you can take one any time. Restore one if a sync went wrong or the saved data got damaged.

## Supported raids

**WoW Forever** (client interface `16001`): Barrow Deeps (10), Hyjal Summit (20), Onyxia's Lair (40).
- Loot tables and instance IDs aren't published yet. Raids are matched by **instance name**, and **every epic+ item that drops is learned** into the catalogue under "Seen in raid". Until then, add items by shift-clicking their links into the catalogue's link box.
- **Onyxia's Lair (Forever)** shows the Classic Onyxia loot for now, tagged "(classic)".
- Future raids go in [Data/Forever.lua](Data/Forever.lua), with their card art in [Data/RaidMeta.lua](Data/RaidMeta.lua).

**Classic raids**: Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, AQ20, AQ40 and Naxxramas, generated from AtlasLootClassic. On a Classic Era client (`11509`) these are the only raids. On the Forever client they follow the Forever raids, tagged *Classic*.

To regenerate the classic tables after AtlasLoot updates:

```
luajit tools/gen_classic_raids.lua "<WoW>/_forever_/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids/data.lua" > Data/Raids.lua
```

## Commands

| Command | Who | |
|---|---|---|
| `/idwlc` or `/reserve` | everyone | Open the addon |
| `/idwlc hr <item>` / `sr <item>` | everyone | Add or remove an item on your hard or soft list for the live raid |
| `/idwlc status` / `list` | everyone | Your active and standby reserves, or everyone's reserves |
| `/idwlc settings` | everyone | Settings tab |
| `/idwlc roster` | leader | Roster tab |
| `/idwlc approve [hard soft]` | leader | Open the approval prompt, or approve counts directly |
| `/idwlc raid <key>` / `raids` | leader | Start reserves for a raid, or list raid keys |
| `/idwlc lock` / `unlock` | leader | Lock or unlock reserves |
| `/idwlc loot` | everyone | Loot window |
| `/idwlc ledger` | everyone | Ledger tab |
| `/idwlc add <item>` | leader | Add an item to the loot window by hand |
| `/idwlc reset` / `sync` | leader | Collect everyone's reserves again, or re-broadcast |

## Master Loot settings

Saved account wide. Used the next time you approve counts for a raid; the counts you approve are remembered per raid.

| Setting | Default | Meaning |
|---|---|---|
| Hard reserves per player | 1 | 1–10 |
| Soft reserves per player | 3 | 1–10 |
| Allow double soft reserve | off | A player may spend two soft reserves on one item |
| Winning uses up the reserve | on | The winner's reserve on that item is removed |
| Announce channel | Raid warning | Where rolls and awards are announced |
| Roll timeout | 30 s | 0 = rolls never close by themselves |
| Main spec / off spec | on | Unreserved items: `/roll 100` beats `/roll 99` |
| Plus-ones | off | Unreserved items: fewer items won this run goes first |
| Soft reserve bonus | 0 (off) | Added per earlier run reserved without winning; cap 30 |
| Disenchanter / bank holder | empty | Who unwanted items go to; empty = the loot master |

## Project layout

```
PRD.md                  Product requirements (source of truth for scope)
IDontWannaLC.toc        Addon manifest (Forever 16001, Classic Era 11509, TBC Anniversary 20506)
Core/Engine.lua         Pure rules: reserves, resolve, rolls, slot groups, roster status, stats. No WoW API, unit tested
Core/Init.lua           Namespace, SavedVariables, events, API compatibility, internal callbacks
Core/Comm.lua           Addon-message protocol, throttled queue, pauses during boss encounters
Core/Reserves.lua       Player lists + leader approval, lock and sync
Core/Roster.lua         Leader's inventory of the raid, whisper reminders
Core/Stats.lua          Boss kills and clears per raid
Core/Ledger.lua         Loot ledger: every run's drops and awards, guild sync, backups
Core/Loot.lua           Drop detection, roll tracking, award announcements
Core/RaidDataAPI.lua    Raid lookup, instance detection, learned loot, loot grouped by slot
Core/Slash.lua          /idwlc commands
Data/Raids.lua          Classic loot tables (generated - see tools/)
Data/Forever.lua        WoW Forever raids
Data/RaidMeta.lua       Raid card icon / colour / optional artwork
UI/MainFrame.lua        The tabbed main window
UI/RaidList.lua         Raids tab: raid cards
UI/RaidView.lua         A raid's boss and loot catalogue, your lists
UI/RosterPanel.lua      Roster tab (raid leader)
UI/LedgerPanel.lua      Ledger tab: past raids, what dropped, who got what
UI/SettingsPanel.lua    Settings tab: General, Master Loot
UI/ApprovePopup.lua     Leader's approval prompt
UI/LootFrame.lua        Loot window (everyone; the raid leader runs rolls and awards from it)
UI/RollPopup.lua        Small "item is up" popup when the loot window is closed
UI/Tooltip.lua          Reserve info on item tooltips
tests/                  Unit tests (luajit tests/run.lua) + UI smoke test against a mock WoW API (luajit tests/smoke.lua .)
docs/superpowers/plans  Implementation plans written against the PRD
```

## Development

```bash
bash scripts/check.sh
```

This runs the same checks CI runs: a parse check, a `.toc` completeness check, the unit tests and the UI smoke test.

To install, copy or symlink this folder into `World of Warcraft/_forever_/Interface/AddOns/IDontWannaLC` (or `_classic_era_` for testing).

## Known gaps / next steps

- **Not tested in game yet.** The UI and event wiring need a live test in a raid; the smoke test only runs against a mock of the WoW API.
- **Raid card graphics are placeholders**: an in-game item icon and an accent colour per raid. Proper artwork can be added per raid through the `art` field in [Data/RaidMeta.lua](Data/RaidMeta.lua).
- **WoW Forever loot method is unconfirmed.** The addon assumes the raid leader collects the items and trades them out. Check in game, for example with `/dump C_PartyInfo.GetLootMethod()`.
- **Addon messages are restricted during boss encounters** on the modern client. The send queue pauses during encounters and drains afterwards, so approve and lock before pulls.
- **Forever loot tables and boss counts** are empty until items drop or the data is filled in, so those raid cards show progress only once the game reports a lockout.
- **Cross-realm names** are only partly handled: a player's own client recognises itself under `Name-Realm`, but the roll tracker and roster have not been exercised with mixed-realm raids.
- **If raid lead passes to someone without the addon** while reserves are locked, nobody can unlock until lead passes back.
- **Soft reserve bonus and plus-ones use the loot master's own data.** A loot master who missed earlier runs (and hasn't synced their ledger) will compute a smaller bonus than the raid leader would.
- **A raider who reloads mid-loot** loses the current loot window contents (the ledger keeps what it already recorded); only the loot master's list survives a reload.
- **Plus-one counts live on each client.** A loot master who joined late counts only the wins their client saw.
- **Trade detection** relies on the game's trade events and has not been tried in the client; the "Handed out" button is the fallback.
- **Ledger sync needs the raid leader online.** Only the leader's copy is a source, so a run can't be fetched while they are offline, and runs recorded before sync existed have no shared ID to offer.
