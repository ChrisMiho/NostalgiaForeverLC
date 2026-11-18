---
paths:
  - "Core/Comm.lua"
---
- Addon messages are under 255 bytes, `^`-separated, sent with prefix `IDWLC` (`Addon.PREFIX`).
- Raid business messages (the `RAID_ONLY` set) are accepted only over the RAID channel, never from whispers (R70).
