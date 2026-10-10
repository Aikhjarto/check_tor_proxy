# check_tor_proxy

A Nagios/Icinga plugin that checks whether a proxy exits to the Tor network,
or with `-N` that it does not.
It asks the Tor Project's check service, https://check.torproject.org/api/ip,
through the proxy, which answers whether the request came from a Tor exit
node. A bash script, using curl, or wget if curl is not installed.

```sh
check_tor_proxy -H localhost                       # Tor's SOCKS port 9050
check_tor_proxy -H proxy.example.org -T http       # an HTTP proxy such as Privoxy on port 8118
check_tor_proxy -H proxy.example.org -T http -p 3128 -w 10 -c 20
check_tor_proxy -H proxy.example.org -T http -N    # a proxy that must not go through Tor
```

```
TOR PROXY OK - socks5 proxy localhost:9050 exits to the Tor network via 185.220.101.4 | time=2.315s;;;0
TOR PROXY CRITICAL - http proxy proxy.example.org:8118 does not exit to the Tor network | time=0.203s;;;0
```

| Option | Meaning |
|---|---|
| `-H` | Host name or address of the proxy (required) |
| `-p` | Port of the proxy (default: 9050 for socks5, 8118 for http) |
| `-T` | Type of the proxy: `socks5`, e.g. Tor itself, or `http`, e.g. Privoxy in front of Tor (default: socks5) |
| `-t` | Timeout in seconds for the whole request (default: 30) |
| `-w`, `-c` | WARNING or CRITICAL if the answer takes longer than this many seconds |
| `-C` | Tool to use, `curl` or `wget` (default: curl if installed, else wget) |
| `-u` | URL to ask (default: https://check.torproject.org/api/ip) |
| `-i` | Also show the exit IP if it is not a Tor exit |
| `-N` | Expect a proxy that does not exit to the Tor network |
| `-h`, `-V` | Show the help or the version |

## States

- **OK**: the request came from a Tor exit node; the output names its IP
- **CRITICAL**: the request did not come from a Tor exit node, the proxy
  cannot be reached or fails, or it did not answer within `-t`
- With `-N` the first two are swapped: **OK** if the request did not come
  from a Tor exit node, **CRITICAL** if it did. Use it for proxies that must
  not route through Tor, e.g. a second proxy next to the Tor one.
- **WARNING**/**CRITICAL**: the answer took longer than `-w`/`-c`
- **UNKNOWN**: the check service answered with an error status or something
  unexpected, or the command line is wrong

The plugin prints exactly one line, with the response time as performance
data.

## Notes

- A proxy that does not exit to Tor usually exits with your own address.
  That address is left out of the output, which ends up in logs and
  notifications, unless `-i` is given.
- With `-T socks5`, curl lets the proxy resolve the host name
  (`socks5h://`), so no DNS query bypasses Tor.
- wget cannot use a SOCKS proxy, so `-T socks5` needs curl. With wget, `-t`
  is enforced with `timeout` from coreutils, as wget's own timeout applies to
  each step of the request only.
- Tor usually listens on localhost only. To check its SOCKS port, run the
  plugin on the Tor host, e.g. via NRPE or check_by_ssh.
- An HTTP proxy only exits to Tor if it forwards to Tor; for Privoxy that is
  a line like `forward-socks5t / 127.0.0.1:9050 .` in its configuration.

## Bash completion

`completions/check_tor_proxy` completes the options, host names for `-H`
and the choices of `-T` and `-C`, also when the plugin is called by its full
path. The packages install it; otherwise copy it to bash-completion's
directory:

```sh
install -D -m 0644 completions/check_tor_proxy /usr/share/bash-completion/completions/check_tor_proxy
```

## Tests

```sh
tests/test_check_tor_proxy.sh
tests/test_completion.sh
```

runs the plugin against fake curl and wget commands, and tests the bash
completion.

## License

GPL-2.0-or-later, see [LICENSE](LICENSE).
