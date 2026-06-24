# shellcheck shell=bash
export COLOR_OFF='\033[0m'
export COLOR_BLUE='\033[0;34m'
export COLOR_RED='\033[0;31m'
export COLOR_GREEN='\033[0;32m'
export COLOR_YELLOW='\033[0;33m'

lsfn() {
  fns=(
		b64d
		b64e
		brewsuggest
		browser
		cheat_glow
		check_cert
		cleanmac
		dks
		kbp
		randompass
		timestampd
		timestampe
		vpn
	)
	for fn in "${fns[@]}"; do
		echo "${COLOR_BLUE}[$fn]${COLOR_OFF}\n"
		$fn -h
		echo "\n"
	done
}

b64d() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Decode base64 string.\n\n"
		printf "Usage:\n"
		printf "  b64d <string>   base64 decode the given string.\n"
		;;
	*)
		echo -n "$1" | base64 -d
		;;
	esac
}

b64e() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Encode base64 string.\n\n"
		printf "Usage:\n"
		printf "  b64e <string>   base64 encode the given string.\n"
		;;
	*)
		echo -n "$1" | base64
		;;
	esac
}

brewsuggest() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Suggest useful Homebrew CLI tools and show which are already installed.\n\n"
		printf "Usage:\n"
		printf "  brewsuggest   list suggested tools (✓ installed, ○ missing) and an install command.\n"
		return 0
		;;
	esac

	if ! command -v brew > /dev/null 2>&1; then
		echo "Error: Homebrew not installed (see https://brew.sh)." >&2
		return 1
	fi

	# Curated "name|description" pairs — modern, broadly useful CLI tools.
	local tools=(
		"bat|cat clone with syntax highlighting"
		"eza|modern ls replacement"
		"fd|simple, fast find alternative"
		"ripgrep|fast recursive grep (rg)"
		"fzf|fuzzy finder"
		"jq|JSON processor"
		"yq|YAML processor"
		"gh|GitHub CLI"
		"lazygit|terminal UI for git"
		"lazydocker|terminal UI for docker"
		"k9s|Kubernetes TUI"
		"btop|resource monitor"
		"tldr|simplified, example-driven man pages"
		"dust|intuitive disk usage (du)"
		"duf|friendlier disk free (df)"
		"httpie|human-friendly HTTP client"
		"direnv|per-directory environment loader"
		"zoxide|smarter cd that learns your habits"
	)

	local installed
	installed=$(brew list --formula -1 2>/dev/null)

	local missing=()
	local entry name desc
	for entry in "${tools[@]}"; do
		name="${entry%%|*}"
		desc="${entry#*|}"
		if printf '%s\n' "$installed" | grep -qx "$name"; then
			printf "  ${COLOR_GREEN}✓${COLOR_OFF} %-11s %s\n" "$name" "$desc"
		else
			printf "  ${COLOR_YELLOW}○${COLOR_OFF} %-11s %s\n" "$name" "$desc"
			missing+=("$name")
		fi
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		printf "\nInstall the missing ones:\n  ${COLOR_BLUE}brew install %s${COLOR_OFF}\n" "${missing[*]}"
	else
		printf "\nAll suggested tools are already installed.\n"
	fi
}

browser() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Start a browsh web browser using docker.\n\n"
		printf "Usage:\n"
		printf "  browser           launch the web browser.\n"
		printf "  browser -- <url>  launch the web browser on the given url.\n"
		;;
	*)
		if ! docker info > /dev/null 2>&1; then
			echo "This function uses docker, and it isn't running - please start docker and try again!"
		else
			[ "$1" = "--" ] && shift
			docker run --rm -it browsh/browsh "$@"
		fi
	esac
}

cheat_glow() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Improve cheat sheet lisibility by piping it to glow.\n\n"
		printf "Usage:\n"
		printf "  cheat_glow <cheat_sheet>   enhance cheat sheet render.\n"
		;;
	*)
		cheat "$@" | glow --width=150
		;;
	esac
}

check_cert() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Print certificate infos for the given domain.\n\n"
		printf "Usage:\n"
		printf "  check_cert <url>   Print cert infos.\n"
		;;
	*)
		curl -w '%{certs}' -k "$1"
		;;
	esac
}

_cleanmac_path() {
	local apply="$1" dir="$2" size
	if [ ! -d "$dir" ]; then
		echo "[skip] $dir (not found)"
		return 0
	fi
	size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
	[ -z "$size" ] && size="0B"
	if [ "$apply" = true ]; then
		echo "[clean] $dir ($size)"
		# Remove the contents, keep the directory itself
		find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
	else
		echo "[dry] $dir ($size)"
	fi
}

cleanmac() {
	case "$1" in
	-h | --help | "")
		printf "Description:\n"
		printf "  Reclaim disk space on macOS: caches, logs, trash, Homebrew, DNS cache.\n"
		printf "  Safe by default — shows what would be freed; deletes nothing without --yes.\n\n"
		printf "Usage:\n"
		printf "  cleanmac                 dry run: show reclaimable space per target.\n"
		printf "  cleanmac --yes           clean every target.\n"
		printf "  cleanmac --yes <target>  clean only the given target(s).\n\n"
		printf "Targets:\n"
		printf "  caches   user cache files (~/Library/Caches)\n"
		printf "  logs     user log files (~/Library/Logs)\n"
		printf "  trash    empty the Trash (~/.Trash)\n"
		printf "  brew     Homebrew cache and outdated versions\n"
		printf "  dns      flush the DNS resolver cache + purge stale VPN resolvers\n"
		return 0
		;;
	esac

	if [ "$(uname)" != "Darwin" ]; then
		echo "Error: cleanmac only runs on macOS." >&2
		return 1
	fi

	local apply=false
	if [ "$1" = "--yes" ] || [ "$1" = "-y" ]; then
		apply=true
		shift
	fi

	local targets=("$@")
	if [ "${#targets[@]}" -eq 0 ]; then
		targets=(caches logs trash brew dns)
	fi

	local target
	for target in "${targets[@]}"; do
		case "$target" in
		caches) _cleanmac_path "$apply" "$HOME/Library/Caches" ;;
		logs) _cleanmac_path "$apply" "$HOME/Library/Logs" ;;
		trash) _cleanmac_path "$apply" "$HOME/.Trash" ;;
		brew)
			if ! command -v brew >/dev/null 2>&1; then
				echo "[skip] Homebrew not installed"
			elif [ "$apply" = true ]; then
				echo "[clean] Homebrew cache"
				brew cleanup -s
			else
				echo "[dry] brew cleanup -s ($(du -sh "$(brew --cache)" 2>/dev/null | awk '{print $1}') cached)"
			fi
			;;
		dns)
			if [ "$apply" = true ]; then
				echo "[clean] DNS resolver cache"
				# Purge resolvers orphaned by a VPN tunnel that wasn't torn
				# down cleanly (safe: skipped while a tunnel is up).
				_vpn_purge_stale_resolvers
				sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
			else
				echo "[dry] flush DNS resolver cache + purge stale VPN resolvers"
			fi
			;;
		*)
			echo "Error: unknown target '$target' (see 'cleanmac -h')." >&2
			return 1
			;;
		esac
	done

	if [ "$apply" = false ]; then
		printf "\nDry run — nothing deleted. Re-run with 'cleanmac --yes' to apply.\n"
	fi
}

dks() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Decode a kubernetes secret by its name and optionally its namespace.\n\n"
		printf "Usage:\n"
		printf "  dks <secret_name> [namespace]  decode kubernetes secret given its name and optionally its namespace as a second argument.\n"
		;;
	*)
		if [ -n "$2" ]; then
			kubectl -n "$2" get secret "$1" -oyaml | yq '.data | map_values(. | @base64d)'
		else
			kubectl get secret "$1" -oyaml | yq '.data | map_values(. | @base64d)'
		fi
		;;
	esac
}

kbp() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Kill the process running on a given port.\n\n"
		printf "Usage:\n"
		printf "  kbp <port_number>   kill process using the given port.\n"
		;;
	*)
		local pids
		pids=$(lsof -ti :"$1" 2>/dev/null)
		if [ -z "$pids" ]; then
			echo "No process found listening on port $1."
			return 1
		fi
		# shellcheck disable=SC2086
		kill -9 $pids
		;;
	esac
}

randompass() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Generate a password with the given length.\n\n"
		printf "Usage:\n"
		printf "  randompass <password_length>   generate a password with the given length.\n"
		;;
	*)
		local length="${1:-24}"
		case $length in
		*[!0-9]* | '')
			echo "Error: length must be a positive integer (got '$length')." >&2
			return 1
			;;
		esac
		if [ "$length" -lt 4 ]; then
			echo "Error: length must be at least 4 (password needs an upper, a lower, a digit and a special char)." >&2
			return 1
		fi
		while true; do
			local password
			password=$(LC_ALL=C tr -dc 'A-Za-z0-9=!?%~_-' < /dev/urandom 2>/dev/null | head -c "$length")
			[[ $password != *[=\!?\%~_-]* ]] && continue
			[[ $password != *[A-Z]* ]] && continue
			[[ $password != *[a-z]* ]] && continue
			[[ $password != *[0-9]* ]] && continue
			printf '%s\n' "$password"
			break
		done
		;;
	esac
}

timestampd() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Show human readable version of a timestamp date.\n\n"
		printf "Usage:\n"
		printf "  timestampd <timestamp>   print a human readable date.\n"
		;;
	*)
		if [ "$(uname)" = "Darwin" ]; then
			date -r "$1"
		elif [ "$(uname)" = "Linux" ]; then
			date -d @"$1"
		else
			echo "Error: unsupported OS"
		fi
		;;
	esac
}

timestampe() {
	case "$1" in
	-h | --help)
		printf "Description:\n"
		printf "  Show timestamp from a human readable date.\n\n"
		printf "Usage:\n"
		printf "  timestampe <date>   print the timestamp of a date (date in format 'YYYY-mm-ddTHH:MM:ss').\n"
		;;
	*)
		if [ "$(uname)" = "Darwin" ]; then
			date -j -f "%Y-%m-%dT%H:%M:%S" "$1" "+%s" 2>/dev/null || date -j -f "%Y-%m-%d" "$1" "+%s"
		elif [ "$(uname)" = "Linux" ]; then
			date -d "$1" "+%s"
		else
			echo "Error: unsupported OS"
		fi
		;;
	esac
}

# Remove scoped resolvers (/etc/resolver/*) that point into the VPN subnet
# (10.8.0.0/24) but ONLY when no WireGuard tunnel is currently up. These are
# left behind when a tunnel is not torn down cleanly (e.g. reboot without
# 'vpn down'), and otherwise break DNS for the scoped domains until removed.
_vpn_purge_stale_resolvers() {
	[ -d /etc/resolver ] || return 0
	if [ -n "$(sudo wg show interfaces 2>/dev/null)" ]; then
		return 0 # a tunnel is up; its resolvers are legitimate
	fi
	local r
	for r in /etc/resolver/*; do
		[ -e "$r" ] || continue
		if grep -q 'nameserver 10\.8\.0\.' "$r" 2>/dev/null; then
			echo "  removing stale resolver $r"
			sudo rm -f "$r"
		fi
	done
}

vpn() {
	case "$1" in
	-h | --help | "")
		printf "Description:\n"
		printf "  Manage WireGuard VPN tunnels through wg-quick.\n\n"
		printf "Usage:\n"
		printf "  vpn up <tunnel>     bring the given tunnel up.\n"
		printf "  vpn down <tunnel>   bring the given tunnel down.\n"
		printf "  vpn status [tunnel] show active tunnels (or a single one).\n"
		printf "  vpn list            list available tunnel configs.\n"
		printf "  vpn fix-dns         repair DNS after an unclean teardown.\n"
		;;
	up | down)
		if [ -z "$2" ]; then
			echo "Error: missing tunnel name (see 'vpn list')."
			return 1
		fi
		sudo wg-quick "$1" "$2"
		;;
	status | st)
		if [ -n "$2" ]; then
			# On macOS wg-quick maps a tunnel name to a utunN interface; resolve it.
			local iface
			iface="$(sudo cat "/var/run/wireguard/$2.name" 2>/dev/null)"
			sudo wg show "${iface:-$2}"
		else
			sudo wg show
		fi
		;;
	list | ls)
		local wg_dir
		wg_dir="$(brew --prefix 2>/dev/null)/etc/wireguard"
		if [ ! -d "$wg_dir" ]; then
			echo "No WireGuard config directory found at $wg_dir"
			return 1
		fi
		find "$wg_dir" -maxdepth 1 -name '*.conf' -exec basename {} .conf \; 2>/dev/null \
			|| echo "No tunnel configs in $wg_dir"
		;;
	fix-dns | fix)
		if [ "$(uname)" != "Darwin" ]; then
			echo "Error: vpn fix-dns only runs on macOS." >&2
			return 1
		fi
		echo "[vpn] Repairing DNS after an unclean tunnel teardown"
		# 1. Drop scoped resolvers left behind by a dead tunnel.
		_vpn_purge_stale_resolvers
		# 2. Reset every network service back to DHCP-provided DNS. This undoes
		#    a global 'DNS =' override that wg-quick applies via networksetup and
		#    only restores on 'vpn down' (so a reboot mid-tunnel leaves it stuck).
		local svc
		while IFS= read -r svc; do
			case "$svc" in
			"" | An\ asterisk* | \** ) continue ;;
			esac
			if sudo networksetup -setdnsservers "$svc" "Empty" 2>/dev/null; then
				echo "  reset DNS for $svc"
			fi
		done < <(networksetup -listallnetworkservices 2>/dev/null)
		# 3. Flush the resolver cache.
		sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder 2>/dev/null || true
		echo "[vpn] DNS reset to automatic."
		;;
	*)
		echo "Error: unknown subcommand '$1' (see 'vpn -h')."
		return 1
		;;
	esac
}
