#!/bin/bash
# Tests for check_tor_proxy with fake curl and wget commands.
# Run: tests/test_check_tor_proxy.sh

CHECK="$(cd "$(dirname "$0")/.." && pwd)/check_tor_proxy"
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

# FAKE_ANSWER: tor, notor, garbage, status503, refused, slow and slow_notor (a Tor or non-Tor exit
# after FAKE_SLEEP), timeout (curl only)
# Both fakes log their arguments to FAKE_LOG and write the answer of the Tor check API.
cat > "$FAKE_BIN/answer" <<'FAKE'
#!/bin/bash
case "$FAKE_ANSWER" in
	tor|slow) echo '{"IsTor":true,"IP":"185.220.101.4"}' ;;
	notor|slow_notor) echo '{"IsTor":false,"IP":"81.10.209.36"}' ;;
	garbage) echo '<html>Sorry</html>' ;;
esac
FAKE
cat > "$FAKE_BIN/curl" <<'FAKE'
#!/bin/bash
echo "curl $*" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do
	case "$1" in -o) OUT=$2; shift ;; esac
	shift
done
case "$FAKE_ANSWER" in
	refused) echo "curl: (7) Failed to connect to proxy port 9050 after 1 ms: Could not connect to server" >&2; exit 7 ;;
	timeout) echo "curl: (28) Operation timed out after 1001 milliseconds with 0 bytes received" >&2; exit 28 ;;
	slow|slow_notor) sleep "${FAKE_SLEEP:-0}" ;;
	status503) : > "$OUT"; printf 503; exit 0 ;;
esac
"$(dirname "$0")/answer" > "$OUT"
printf 200
FAKE
cat > "$FAKE_BIN/wget" <<'FAKE'
#!/bin/bash
echo "wget $*" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do
	case "$1" in -O) OUT=$2; shift ;; esac
	shift
done
case "$FAKE_ANSWER" in
	refused) echo "failed: Connection refused." >&2; exit 4 ;;
	slow|slow_notor) sleep "${FAKE_SLEEP:-0}" ;;
	status503) echo "https://check.torproject.org/api/ip:" >&2; echo "2026-10-01 10:00:00 ERROR 503: Service Unavailable." >&2; exit 8 ;;
esac
"$(dirname "$0")/answer" > "$OUT"
FAKE
chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:$PATH"
FAKE_LOG=$(mktemp)
export FAKE_LOG

FAILURES=0
TESTS=0

# expect NAME EXIT_CODE OUTPUT_REGEX [ENV=VALUE ...] -- [ARGS ...]
expect(){
	local name=$1 code=$2 regex=$3 envs=() out rc
	shift 3
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
	shift
	out=$(env "${envs[@]}" "$CHECK" "$@" 2>&1)
	rc=$?
	TESTS=$((TESTS + 1))
	if [ $rc -ne "$code" ] || ! [[ "$out" =~ $regex ]]; then
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: exit %s (expected %s)\n     %s\n' "$name" $rc "$code" "$out"
	else
		printf 'ok   %s\n' "$name"
	fi
}

# expect_log NAME REGEX: the last call of curl or wget matches
expect_log(){
	TESTS=$((TESTS + 1))
	if [[ "$(tail -n 1 "$FAKE_LOG")" =~ $2 ]]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: %s\n' "$1" "$(tail -n 1 "$FAKE_LOG")"
	fi
}

for TOOL in curl wget; do
	TYPE=socks5
	[ $TOOL = wget ] && TYPE=http
	expect "$TOOL: Tor exit" 0 "^TOR PROXY OK - $TYPE proxy p:[0-9]+ exits to the Tor network via 185.220.101.4 \| time=[0-9.]+s;;;0$" \
		FAKE_ANSWER=tor -- -H p -T $TYPE -C $TOOL
	expect "$TOOL: not a Tor exit hides the IP" 2 "^TOR PROXY CRITICAL - $TYPE proxy p:[0-9]+ does not exit to the Tor network \| time=" \
		FAKE_ANSWER=notor -- -H p -T $TYPE -C $TOOL
	expect "$TOOL: not a Tor exit with -i" 2 "does not exit to the Tor network, but via 81.10.209.36 \|" \
		FAKE_ANSWER=notor -- -H p -T $TYPE -C $TOOL -i
	expect "$TOOL: proxy refuses" 2 "^TOR PROXY CRITICAL - $TYPE proxy p:[0-9]+ failed: (curl: \(7\) .*Could not connect to server|Connection refused\.)$" \
		FAKE_ANSWER=refused -- -H p -T $TYPE -C $TOOL
	expect "$TOOL: unexpected answer" 3 "^TOR PROXY UNKNOWN - unexpected answer from https://check.torproject.org/api/ip: <html>Sorry</html>" \
		FAKE_ANSWER=garbage -- -H p -T $TYPE -C $TOOL
	expect "$TOOL: error status" 3 "^TOR PROXY UNKNOWN - https://check.torproject.org/api/ip answered with HTTP status 503" \
		FAKE_ANSWER=status503 -- -H p -T $TYPE -C $TOOL
	expect "$TOOL: slow answer is WARNING" 1 "^TOR PROXY WARNING - .* exits to the Tor network via 185.220.101.4, but took [0-9.]+s, more than 0.1s \| time=[0-9.]+s;0.1;5;0$" \
		FAKE_ANSWER=slow FAKE_SLEEP=0.3 -- -H p -T $TYPE -C $TOOL -w 0.1 -c 5
	expect "$TOOL: slower answer is CRITICAL" 2 "^TOR PROXY CRITICAL - .* but took [0-9.]+s, more than 0.2s" \
		FAKE_ANSWER=slow FAKE_SLEEP=0.3 -- -H p -T $TYPE -C $TOOL -w 0.1 -c 0.2
	# -N: a proxy that must not exit to Tor
	expect "$TOOL -N: not a Tor exit is OK" 0 "^TOR PROXY OK - $TYPE proxy p:[0-9]+ does not exit to the Tor network \| time=[0-9.]+s;;;0$" \
		FAKE_ANSWER=notor -- -H p -T $TYPE -C $TOOL -N
	expect "$TOOL -N -i shows the exit IP" 0 "^TOR PROXY OK - .* does not exit to the Tor network, it exits via 81.10.209.36 \|" \
		FAKE_ANSWER=notor -- -H p -T $TYPE -C $TOOL -N -i
	expect "$TOOL -N: a Tor exit is CRITICAL" 2 "^TOR PROXY CRITICAL - $TYPE proxy p:[0-9]+ exits to the Tor network via 185.220.101.4, but must not \|" \
		FAKE_ANSWER=tor -- -H p -T $TYPE -C $TOOL -N
	expect "$TOOL -N: slow answer is WARNING" 1 "^TOR PROXY WARNING - .* does not exit to the Tor network, but took [0-9.]+s, more than 0.1s \|" \
		FAKE_ANSWER=slow_notor FAKE_SLEEP=0.3 -- -H p -T $TYPE -C $TOOL -N -w 0.1 -c 5
done

expect "curl timeout" 2 "^TOR PROXY CRITICAL - socks5 proxy p:9050 did not answer within 1s$" \
	FAKE_ANSWER=timeout -- -H p -C curl -t 1
# wget's --timeout applies to each step only: timeout(1) limits the whole request
expect "wget timeout" 2 "^TOR PROXY CRITICAL - http proxy p:8118 did not answer within 1s$" \
	FAKE_ANSWER=slow FAKE_SLEEP=5 -- -H p -T http -C wget -t 1

# the proxy URLs the tools are called with
FAKE_ANSWER=tor "$CHECK" -H p >/dev/null
expect_log "socks5 resolves names through the proxy" "^curl .*--proxy socks5h://p:9050 "
FAKE_ANSWER=tor "$CHECK" -H p -T http -p 3128 >/dev/null
expect_log "http proxy and port" "^curl .*--proxy http://p:3128 "
FAKE_ANSWER=tor "$CHECK" -H 2001:db8::1 >/dev/null
expect_log "IPv6 proxy in brackets" "--proxy socks5h://\[2001:db8::1\]:9050 "
FAKE_ANSWER=tor "$CHECK" -H p -T http -C wget >/dev/null
expect_log "wget uses the proxy for https" "-e https_proxy=http://p:8118 "
FAKE_ANSWER=tor "$CHECK" -H p -u https://example.org/ip >/dev/null
expect_log "-u sets the URL" " -- https://example.org/ip$"

# a wrong command line is UNKNOWN
expect "no -H" 3 "^TOR PROXY UNKNOWN - no proxy given, use -H$" --
expect "invalid option" 3 "^TOR PROXY UNKNOWN - invalid option -Z" -- -H p -Z
expect "missing argument" 3 "^TOR PROXY UNKNOWN - option -H needs an argument" -- -H
expect "wrong type" 3 "^TOR PROXY UNKNOWN - -T takes socks5 or http, not 'ftp'$" -- -H p -T ftp
expect "wrong port" 3 "^TOR PROXY UNKNOWN - -p takes a port number, not '99999'$" -- -H p -p 99999
expect "wrong threshold" 3 "^TOR PROXY UNKNOWN - -t, -w and -c take seconds, not 'soon'$" -- -H p -w soon
expect "zero timeout" 3 "^TOR PROXY UNKNOWN - -t must be above 0$" -- -H p -t 0
expect "socks5 needs curl" 3 "^TOR PROXY UNKNOWN - wget cannot use a SOCKS proxy" -- -H p -C wget
expect "unexpected argument" 3 "^TOR PROXY UNKNOWN - unexpected argument 'extra'$" -- -H p extra
expect "version" 0 "^check_tor_proxy [0-9.]+$" -- -V

rm -f "$FAKE_LOG"
echo "$TESTS tests, $FAILURES failures"
[ $FAILURES -eq 0 ]
