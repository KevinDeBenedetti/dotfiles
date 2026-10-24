@AGENTS.md

## Claude Code

- Skills `commit-types`, `readme` and `docs-hub` (from `config/skills/`, installed in
  `~/.claude/skills/`) apply here: invoke them through the Skill tool when the
  task matches, rather than reproducing their rules from memory.
- `config/claude/settings.json` is the guardrail reference and is write-denied
  in the sandbox: propose the exact edit to the owner instead of working
  around it.
- Claude-only slash commands live in `config/claude/commands/`; commands shared
  with other tools live in `config/commands/`.
