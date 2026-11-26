@AGENTS.md

## Claude Code

- The skills of `config/skills/` (installed in `~/.claude/skills/`, listed in
  `AGENTS.md`) apply here: load the one that matches the task rather than
  reproducing its rules from memory. `writing-for-agents` covers every edit
  of a skill, of `AGENTS.md` and of this file.
- `config/claude/settings.json` is the guardrail reference and is write-denied
  in the sandbox: propose the exact edit to the owner instead of working
  around it.
- The slash commands (`/next-issue`, `/commit`, `/pr`, …) are user-invoked
  skills in `config/skills/`, shared with the other tools: there is no
  `commands/` directory any more.
