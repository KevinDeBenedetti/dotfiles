---
title: Proto
---

# Proto

Global [proto](https://moonrepo.dev/proto) toolchain configuration.

## Installation

`os/helpers/proto.sh` installs proto (run automatically with the `base`
profile, and on Debian also when linking dotfiles). It downloads the release tarball of the
version pinned in the script from GitHub, checks it against the SHA-256 pinned
next to it, and installs `proto` and `proto-shim` into `~/.proto/bin`. No
installer script is fetched. Builds are pinned for Linux and macOS, x86_64 and
arm64; `proto upgrade` moves to newer releases afterwards.

> Shell integration is managed by the same script, which adds the following block to `~/.zshrc` if not already present:
>
> ```sh
> export PROTO_HOME="$HOME/.proto"
> export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"
> ```

## Version pinning

All tool versions are declared in `config/proto/.prototools`, which is symlinked to `~/.proto/.prototools` when dotfiles are installed. Setup scripts read this file automatically — no versions are hardcoded in any script.

## Location

| File                       | Symlinked to              |
| -------------------------- | ------------------------- |
| `config/proto/.prototools` | `~/.proto/.prototools`    |

## Managed tools

Every tool is pinned to an exact version in `.prototools`, the source of truth
for the numbers; the `# renovate:` comments there mark the pins Renovate is
configured to bump.

| Tool     | Version                          |
| -------- | -------------------------------- |
| `node`   | Exact version                    |
| `npm`    | `bundled` (ships with that Node) |
| `bun`    | Exact version                    |
| `pnpm`   | Exact version                    |
| `yarn`   | Exact version                    |
| `python` | Exact version                    |
| `go`     | Exact version                    |

## Settings

| Setting                  | Value    | Description                              |
| ------------------------ | -------- | ---------------------------------------- |
| `auto-install`           | `true`   | Automatically install tools when missing |
| `auto-clean`             | `true`   | Clean up old tool versions automatically |
| `pin-latest`             | `global` | Pin `latest` resolves globally           |
| `node.bundled-npm`       | `true`   | Bundle npm with the Node installation    |
| `npm.shared-globals-dir` | `true`   | Share npm global packages directory      |

## Usage

```sh
# Install all tools defined in .prototools
proto install

# Upgrade all tools to their latest version
proto upgrade

# List installed tool versions
proto list
```
