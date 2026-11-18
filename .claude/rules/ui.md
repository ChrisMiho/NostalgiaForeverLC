---
paths:
  - "UI/**/*.lua"
  - "tests/smoke.lua"
---
- The smoke mock returns a no-op function for any unknown frame field or method, so a missing mock fails silently: add each new WoW API you call to the mock in `tests/smoke.lua`.
- For the same reason never keep boolean state in frame fields that may be unset (an unset field reads as a function, which is truthy); use locals.
- Use only API present on every interface listed on the `.toc` `## Interface:` line (`16001` Forever, `11509` Classic Era, `20506` TBC Anniversary), feature-detected as `(C_X and C_X.Fn) or _G.Fn`, as in `Core/Init.lua`.
- Smoke assertions use `check(cond, msg)`.
