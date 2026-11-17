# I Don't Wanna LC

A **raid loot addon for WoW Forever** that runs your raid on **hard and soft reserves** instead of loot council. Everyone in the raid installs it. Players spend their reserves on items before the raid. When something drops, the addon works out who is allowed to roll. **The raid leader still hands out every item themselves.** The addon never distributes loot.

> Status: **draft (v0.2.0)**. Not tested in game yet. See [Known gaps](#known-gaps--next-steps).

## How it works

| Drop | What happens |
|---|---|
| **Legendary or higher** (orange+) | **Restricted.** Nobody can reserve it and there is no roll. The raid leader decides who gets it. |
| **Hard reserved** | Hard reserves beat soft reserves. If one player hard reserved it, it goes to them with no roll. If several did, **only the hard reservers roll**, and soft reserves on that item are ignored. |
| **Soft reserved** | Only the players who soft reserved it may `/roll`. All other rolls are ignored. |
| **Not reserved** | Open `/roll` for everyone. |

### Raid leader: saved rules per raid
- The leader sets how many hard and soft reserves each player gets (`/idwlc set 1 2`), plus a few options. The rules are **saved per raid in the leader's settings**. When the leader forms a new group, picks a raid, or zones into one, that raid's saved rules load and are sent to everyone automatically. Raids with no saved rules use the leader's defaults.
- **Any change is pushed to the raid straight away.** It's announced in raid chat, and every player gets a notice and a raid-warning alert. The reserve window opens to show what changed.
- The leader locks reserves before pulling.

### Players: plan ahead with a priority list
- Open `/idwlc` and browse **any raid like a catalogue**, whether or not you're in it. Click **HR** or **SR** to add an item to that raid's **hard tier** or **soft tier**. You can also shift-click any item link.
- Each tier is a **ranked list** of up to 10 items, longer than the slots you'll get. Reorder it with the up/down arrows.
- **When you join a raid, your reserves are picked automatically from the top of each tier** to match the leader's slot counts. With 1 HR and 2 SR slots, your #1 hard pick and your #1–#2 soft picks are sent; the rest stay on **standby**. If the leader changes the counts, your reserves update to match, so you can never reserve too many or too few.
- Restricted items are skipped, and the next item in the tier moves up. Items you win are taken off your list.

### Authority
- The leader's client is the **authority**. It checks every reserve against the limits, the lock and restricted items, then syncs the full list to the raid. If a reserve is refused, you're told why.
- **When loot drops**, the leader's client picks the item up. It can come from the corpse loot window, from an item the leader receives, or from a link the leader adds by hand. It then shows up in the leader's **loot window** with the decision. The leader clicks **Start roll** and the addon announces who may roll. Everyone eligible gets a popup with a **Roll** button. The addon tracks valid `/roll 100` results, handles ties with re-rolls, and suggests a winner.
- The leader clicks **Award**. The addon announces the winner and uses up that player's reserve. **The leader then loots or trades the item by hand.**
- The addon **only works in raids**: loot tracking runs only in a raid group inside a raid instance. Dungeons are ignored.

## Supported raids

**WoW Forever** (client interface `16001`, first tier unlocks Dec 9, 2026):
- Barrow Deeps (10), Hyjal Summit (20), Onyxia's Lair (40).
- Blizzard hasn't published loot tables or instance IDs yet. To cope with that, raids are matched by **instance name**, and the real ID is learned the first time you zone in. **Every epic+ item that drops is learned** into the reserve browser under "Seen in raid". Until then, players reserve by shift-clicking item links.
- Future raids go in [Data/Forever.lua](Data/Forever.lua). The spring 2027 and summer 2027 raids are announced but not named yet.

**Classic Era** (interface `11509`, useful for testing): Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, AQ20, AQ40 and Naxxramas, with loot tables in [Data/Raids.lua](Data/Raids.lua). *The item IDs were written from memory and need checking against Wowhead.*

## Commands

| Command | Who | |
|---|---|---|
| `/idwlc` or `/reserve` | everyone | Open the reserve window |
| `/idwlc hr <item>` / `sr <item>` | everyone | Add or remove an item in your hard or soft tier for the current raid |
| `/idwlc status` / `list` | everyone | Show your active and standby reserves, or everyone's reserves |
| `/idwlc leader` | leader | Leader panel: settings, lock, all reserves, export |
| `/idwlc loot` | leader | Loot session window |
| `/idwlc set <hard> <soft>` | leader | Reserves per player |
| `/idwlc lock` / `unlock` | leader | Lock or unlock reserves |
| `/idwlc raid <key>` / `raids` | leader | Set the raid (loads its saved rules), or list raid keys |
| `/idwlc add <item>` | leader | Add an item to the loot session by hand |
| `/idwlc reset` / `sync` | leader | Clear all reserves, or re-broadcast them |

## Leader settings

These are saved per raid. The first time you set up a raid, your defaults are used.

| Setting | Default | Meaning |
|---|---|---|
| `hardReserves` | 1 | Hard reserves per player |
| `softReserves` | 2 | Soft reserves per player |
| `restrictedMinQuality` | 5 (Legendary) | This quality and above is restricted |
| `allowDoubleSoft` | off | Lets a player spend two soft reserves on the same item |
| `consumeOnAward` | on | Winning an item uses up that reserve |

## Project layout

```
IDontWannaLC.toc        Addon manifest (Forever 16001, Classic Era 11509, TBC Anniversary 20506)
Core/Engine.lua         Pure rules engine (reserves, resolve, rolls, serialization). No WoW API, unit tested
Core/Init.lua           Namespace, SavedVariables, events, API compatibility, internal callbacks
Core/Comm.lua           Addon-message protocol, throttled queue, pauses during boss encounters
Core/Reserves.lua       Player picks + leader authority and sync
Core/Loot.lua           Drop detection, roll tracking, award announcements, member roll popup state
Core/RaidDataAPI.lua    Raid lookup, instance detection, learned loot
Core/Slash.lua          /idwlc commands
Data/Raids.lua          Classic loot tables
Data/Forever.lua        WoW Forever raids
UI/*.lua                Reserve window, leader panel, loot window, roll popup
tests/                  Unit tests (luajit tests/run.lua) + UI smoke test against a mock WoW API (luajit tests/smoke.lua .)
```

## Development

```bash
luajit tests/run.lua
luajit tests/smoke.lua .
```

To install, copy or symlink this folder into `World of Warcraft/_forever_/Interface/AddOns/IDontWannaLC` (or `_classic_era_` for testing).

## Known gaps / next steps

- **Not tested in game yet.** The UI and event wiring need a live test in a raid.
- **WoW Forever loot method is unconfirmed.** Modern WoW has no master loot. The addon assumes the raid leader collects the items (from the loot window, or items that end up in their bags) and trades them out. Check this in game, for example with `/dump C_PartyInfo.GetLootMethod()`.
- **Addon messages are restricted during boss encounters** on the modern client. The send queue pauses during encounters and drains afterwards, so sync reserves before pulls.
- **Forever loot tables** are empty until items drop or the data is filled in. **Classic item IDs** need checking.
- Only the raid leader is the authority. Assistant or loot-master delegation, MS/OS rolls for open items, a reserve import from sites like softres.it, and an award history UI would all be useful next.
