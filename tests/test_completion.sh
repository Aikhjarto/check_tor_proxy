#!/bin/bash
# Tests for the bash completion in completions/check_tor_proxy.
# Run: tests/test_completion.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/check_tor_proxy"
COMPLETION="$ROOT/completions/check_tor_proxy"
HOSTS=$(mktemp)
trap 'rm -f "$HOSTS"' EXIT
# host names come from HOSTFILE
printf '%s\n' '192.0.2.1 proxy.example.com' '192.0.2.2 privoxy.example.com' > "$HOSTS"

FAILURES=0
TESTS=0

# the candidates, one per line, bash offers for the last argument, which may be empty
complete_words(){
	HOSTFILE="$HOSTS" bash -c 'source "$1"; shift; COMP_WORDS=(check_tor_proxy "$@"); COMP_CWORD=$#
		_check_tor_proxy; printf "%s\n" "${COMPREPLY[@]}"' bash "$COMPLETION" "$@" | grep . | sort
}

# expect NAME EXPECTED ACTUAL
expect(){
	TESTS=$((TESTS + 1))
	if [ "$2" == "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: expected\n%s\n     got\n%s\n' "$1" "$2" "$3"
	fi
}

TESTS=$((TESTS + 1))
if bash -n "$COMPLETION"; then echo "ok   syntax"; else FAILURES=$((FAILURES + 1)); echo "FAIL syntax"; fi

# the options -h lists
HELP_OPTIONS=$("$CHECK" -h | sed -n 's/^ \(-[[:alpha:]]\)\t.*/\1/p' | sort)
expect "-h lists options" 12 "$(wc -l <<< "$HELP_OPTIONS")"
expect "exactly the options of -h" "$HELP_OPTIONS" "$(complete_words "")"
expect "option prefix" "-N" "$(complete_words -H p -N)"
expect "types" "$(printf '%s\n' http socks5)" "$(complete_words -T "")"
expect "type prefix" "socks5" "$(complete_words -T s)"
expect "tools" "$(printf '%s\n' curl wget)" "$(complete_words -C "")"
expect "host names" "$(printf '%s\n' privoxy.example.com proxy.example.com)" "$(complete_words -H pr)"
for OPTION in -p -t -w -c -u; do
	expect "no candidates for $OPTION" "" "$(complete_words $OPTION "")"
done
expect "registered for check_tor_proxy" "complete -F _check_tor_proxy check_tor_proxy" \
	"$(bash -c 'source "$1"; complete -p check_tor_proxy' bash "$COMPLETION")"

echo "$TESTS tests, $FAILURES failures"
[ $FAILURES -eq 0 ]
