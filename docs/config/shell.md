# Shell

Shell environment variables and utility functions sourced by `.zshrc`.

## Location

| File                        | Symlinked to                      | Description           |
| --------------------------- | --------------------------------- | --------------------- |
| `config/shell/env.sh`       | `~/.config/dotfiles/env.sh`       | Environment variables |
| `config/shell/functions.sh` | `~/.config/dotfiles/functions.sh` | Utility functions     |

## env.sh

Defines environment variables for optional integrations. Secrets and machine-specific
values go in `~/.config/dotfiles/env.local.sh`, which is not tracked by git.

```sh
# Example env.local.sh (not tracked)
export CONTEXT7_API_KEY="your-real-key"
```

## functions.sh

Color constants and utility functions available in every interactive shell session.

### Color constants

| Variable       | Color  |
| -------------- | ------ |
| `COLOR_OFF`    | Reset  |
| `COLOR_BLUE`   | Blue   |
| `COLOR_RED`    | Red    |
| `COLOR_GREEN`  | Green  |
| `COLOR_YELLOW` | Yellow |

### Functions

#### `lsfn`

List all available utility functions with their help text.

```sh
lsfn
```

#### `b64d`

Decode a base64 string.

```sh
b64d <string>
```

#### `b64e`

Encode a string to base64.

```sh
b64e <string>
```

#### `browser`

Launch the [browsh](https://www.brow.sh) terminal web browser via Docker.

```sh
browser               # open browser
browser -- <url>      # open on a specific URL
```

#### `cheat_glow`

Render a [cheat](https://github.com/cheat/cheat) sheet through [glow](https://github.com/charmbracelet/glow) for better readability.

```sh
cheat_glow <sheet>
# Aliased as: cs <sheet>
```

#### `check_cert`

Print TLS certificate details for a domain.

```sh
check_cert <url>
```

#### `dks`

Decode all values of a Kubernetes secret (base64 → plaintext).

```sh
dks <secret-name> [namespace]
```

#### `kbp`

Kill the process listening on a given port.

```sh
kbp <port>
```

#### `randompass`

Generate a random password containing uppercase, lowercase, digits, and special characters.

```sh
randompass [length]   # default length: 24
```

#### `timestampd`

Convert a Unix timestamp to a human-readable date.

```sh
timestampd <timestamp>
```

#### `timestampe`

Convert a human-readable date to a Unix timestamp.

```sh
timestampe <date>     # format: YYYY-mm-ddTHH:MM:ss  or  YYYY-mm-dd
```
