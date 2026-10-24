# Security policy

These dotfiles install packages and write system configuration — partly as
`root` on Debian servers (SSH, firewall, sysctl) — and they configure the
guardrails of AI coding agents. Reports of anything that weakens a machine set
up with them are welcome.

## Reporting a vulnerability

Please **do not open a public issue**. Report privately through GitHub:
**Security → Report a vulnerability** on this repository (private
vulnerability reporting). Include the affected script or config file, the
version (tag or commit SHA) and, if possible, a reproduction.

You can expect an acknowledgement within a few days. Fixes ship in the next
release.

## Supported versions

Only the latest release and `main` receive fixes.

## Using these dotfiles safely

- **Read before you run.** The one-liner runs `init.sh` straight from GitHub
  and the profiles use `sudo`: review the scripts first, or clone a tagged
  release and run it locally.
- **Fork and adapt.** The configs carry personal choices (installed apps, the
  network domains AI agents may reach, signing setup); review them before
  applying them to your machine.
- **Keep secrets out of the repository.** Machine-specific values go in the
  untracked `~/.gitconfig.local`, `~/.zshrc.local` and
  `~/.config/dotfiles/env.local.sh`, never in `config/`; do not export API keys
  from the shell (see [`docs/config/shell.md`](docs/config/shell.md)).
- **Agent guardrails are defence in depth.** The Claude Code sandbox and the
  secret deny rules are the boundary; the regex hooks only catch mistakes (see
  [`docs/config/claude-code.md`](docs/config/claude-code.md)).
