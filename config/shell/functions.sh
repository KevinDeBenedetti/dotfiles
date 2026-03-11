local COLOR_OFF='\033[0m'
local COLOR_BLUE='\033[0;34m'
local COLOR_RED='\033[0;31m'
local COLOR_GREEN='\033[0;32m'
local COLOR_YELLOW='\033[0;33m'

lsfn() {
  fns=(
		b64d
		b64e
		browser
		cheat_glow
		check_cert
		dks
		kbp
		randompass
		timestampd
		timestampe
	)
	for fn in ${fns[@]}; do
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
			docker run --rm -it browsh/browsh "$1"
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
		kill -9 $(lsof -i :$1 | tail -n +2 | awk '{print $2}')
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
		while true; do
			local password=$(LC_ALL=C tr -dc 'A-Za-z0-9=!?%~_-' < /dev/urandom | head -c ${1:-24})
			[[ $password != *[=\!?\%~_-]* ]] && continue
			[[ $password != *[A-Z]* ]] && continue
			[[ $password != *[a-z]* ]] && continue
			[[ $password != *[0-9]* ]] && continue
			echo "$password"
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
