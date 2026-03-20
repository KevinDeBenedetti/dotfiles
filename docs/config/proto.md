# Proto

Global [proto](https://moonrepo.dev/proto) toolchain configuration.

## Installation

proto is installed via its official installer (run automatically with the `base` profile):

```sh
curl -fsSL https://moonrepo.dev/install/proto.sh | bash -s -- --no-profile
```

> `--no-profile` skips patching shell files. Shell integration is managed by `os/helpers/proto.sh`, which adds the following block to `~/.zshrc` if not already present:
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

| Tool     | Version               |
| -------- | --------------------- |
| `node`   | `latest`              |
| `npm`    | `bundled` (with Node) |
| `bun`    | `latest`              |
| `pnpm`   | `latest`              |
| `yarn`   | `latest`              |
| `python` | `3.12.13`             |

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
