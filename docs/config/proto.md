# Proto

Global [proto](https://moonrepo.dev/proto) toolchain configuration.

## Location

| File                       | Symlinked to    |
| -------------------------- | --------------- |
| `config/proto/.prototools` | `~/.prototools` |

## Managed tools

| Tool   | Version               |
| ------ | --------------------- |
| `bun`  | `latest`              |
| `node` | `latest`              |
| `npm`  | `bundled` (with Node) |
| `pnpm` | `latest`              |

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
