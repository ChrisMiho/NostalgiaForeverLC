# Working with Claude Code in this repo

How agent guidance is organised here, and where a new piece of it belongs. Based on the
[Claude Code best practices](https://code.claude.com/docs/en/best-practices).

## Where does this go

| What you want to write down | Where it goes |
| --- | --- |
| A fact Claude can't find that matters everywhere | `CLAUDE.md` |
| A fact that matters in one area of the code | `.claude/rules/<area>.md` with a `paths:` frontmatter list |
| A multi-step procedure | `.claude/skills/<name>/SKILL.md` (`disable-model-invocation: true` if it has side effects outside the repo) |
| A rule with zero exceptions | a hook in `.claude/settings.json` |
| Something that must never be read or run | `permissions.deny` in `.claude/settings.json` |
| A personal preference | `CLAUDE.local.md` (gitignored) |

Before writing anything down, ask two questions: could an agent find it by reading the code,
and would it actually look? If both answers are yes, leave it out.

Current rules: `engine.md`, `ui.md`, `comm.md`, `data.md` in `.claude/rules/`.
Skills and agents: `add-forever-raid` (skill), `prd-reviewer` (agent).

## What is enforced today

- **PreToolUse hook** (`scripts/hooks/protect-generated.sh`): blocks Edit/Write on `Data/Raids.lua`.
  It is generated from AtlasLoot; a hand edit is lost on the next regeneration, so there is no
  case where editing it is right.
- **Stop hook**: runs `bash scripts/check.sh --quiet` when Claude finishes and sends it back to
  work if the check fails. "Done" always means the check passes, so there is no exception.
- **CI** (`.github/workflows/test.yml`): runs the same `scripts/check.sh` on every push and pull
  request, so a session that skipped the hook still can't merge a failing change.

## Session habits that can't be codified

- Write specific prompts: name the files, and say what "done" looks like.
- Brainstorm, then write it into `PRD.md` or a spec, then build it in a fresh session.
- `/clear` between unrelated tasks, and after two failed corrections on the same problem.
- Ask for evidence: the command that was run and its output, not "tests pass".
- Review with the `prd-reviewer` agent, and tell it "skip style".

## Deliberately not added yet

| Not added | Add it when |
| --- | --- |
| A release skill | a packaging/release process exists |
| `.worktreeinclude` | there are gitignored files a fresh checkout needs |
| MCP servers | one is actually needed; `gh` already covers GitHub |

## Maintenance

- When Claude gets something wrong twice, add one line in the right place from the table above.
- When `CLAUDE.md` passes 60 lines, move area-specific facts into `.claude/rules/`.
- Run `/doctor prompt-audit` after big refactors.
