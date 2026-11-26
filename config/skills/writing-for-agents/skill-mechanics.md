# Skill mechanics

What changes when the document is a skill. The house rules of the dotfiles
repository are in its `docs/config/skills.md`.

## Invocation

| Kind          | Frontmatter                                                         | Description is read by | Costs          |
| ------------- | ------------------------------------------------------------------- | ---------------------- | -------------- |
| model-invoked | `name`, `description`                                               | the model, every turn  | context load   |
| user-invoked  | plus `disable-model-invocation: true` and the two `opencode/*` keys | the owner, in `/` menu | cognitive load |

- Choose **model-invoked** when the agent must reach the skill on its own, or
  another skill must load it. Its description is a pointer: what it is, then
  the triggers.
- Choose **user-invoked** for a workflow the owner starts by hand
  (`/next-issue`, `/commit`). Its description is one line for a person.
- A skill reaches another by naming it: "load the `git-workflow` skill".
  Only model-invoked skills can be reached that way. Material two
  user-invoked skills share goes in a model-invoked skill, or in a plain
  file both point to.

## Layout

```text
config/skills/<name>/
├── SKILL.md        steps, and the reference every run needs
└── <topic>.md      reference only some runs need, linked as ./<topic>.md
```

- `name` equals the folder name. Keep `SKILL.md` well under 500 lines.
- No tool-specific syntax: write "load the skill", "a sub-agent when the tool
  has them", so the same file works in Claude Code, OpenCode and VS Code.
- Split a skill in two when part of it has its own trigger word, or when the
  later steps make the agent rush the first ones.
