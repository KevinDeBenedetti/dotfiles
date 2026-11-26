# Global agent rules

Rules of the owner of this machine, for every project and every AI coding
agent (Claude Code, OpenCode, VS Code Copilot). A project's own `AGENTS.md` /
`CLAUDE.md` adds to them and wins on what is specific to that project.

<!-- Single source: config/agents/AGENTS.md in the dotfiles repository, linked
     by os/helpers/links.sh to ~/.claude/AGENTS.md (imported by CLAUDE.md),
     ~/.config/opencode/AGENTS.md and ~/.copilot/copilot-instructions.md.
     Edit it there only. Every line is read on every turn: keep it short. -->

## Git

- The owner stages, commits and pushes. Hand each of those steps over as a
  runnable one-line command (`git-workflow` skill), the message a Conventional
  Commit (`commit-types` skill). Read-only git and `gh` are yours.
- Work that ends in a commit starts on a branch of its own, off `main` /
  `dev`: hand the branch command first.

## Writing

- Everything written into a project or onto GitHub (code, comments, docs,
  commit messages, pull requests, issues) is in English and reads as the
  owner's own work: no AI attribution, no `Co-Authored-By` naming an AI.
- Talk with the owner in the language they write in.
- State only what you read in the repository or ran: commands, paths, options
  and links are verified, never written from memory.

## Secrets and infrastructure

- Secrets stay unread and unwritten: `.env*`, `*.pem`, `*.key`, `~/.ssh`,
  `~/.aws`, `~/.gnupg`. Hand over the concrete values to paste.
- A public repository holds no real IP address, host name or account name:
  use placeholders (`<host>`, `example.com`).
- `kubectl` is read-only for agents. Hand mutating commands to the owner.
- A project that publishes host ports follows `~/.claude/dev-ports.md`.

## Skills

Personal skills are installed for every tool. Load the matching skill before
the work it covers instead of improvising: `diagnosing-bugs` before fixing
something broken, `tdd` where the project has tests, `code-review` before a
hand-over, `grilling` when a request leaves decisions open. A denied command
is a guardrail: hand the command to the owner rather than working around it.
