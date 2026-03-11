# Changelog

All notable changes to this project will be documented here.

---

## [2.0.3] — 2026-03-11

### Security

- **Zone filename validation** — manifest parsing now requires filenames to match `^[a-z]{2}-aggregated\.zone$`; previously `grep '\.zone$'` accepted any suffix including path-traversal patterns
- **JSON payload hardening** — all Slack webhook payloads now built with `jq` instead of manual string interpolation; eliminates backslash/control-character injection that could produce malformed JSON and silent delivery failures
- **Webhook config no longer sourced** — both scripts now parse `/usr/local/etc/geoblock-webhook.conf` with `grep`+`tr` (strips surrounding quotes, validates `https://` prefix) instead of `. "$WEBHOOK_CONF"`; prevents arbitrary code execution if the file is tampered with
- **Unpredictable temp files** — all temp paths now use `mktemp` instead of fixed `/tmp/filename` strings, eliminating TOCTOU/symlink attack surface
- **`--fail` on zone downloads** — `curl` calls that download zone files now use `-f` so HTTP 4xx/5xx responses are rejected rather than silently written into the blocklist
- **Interface name sanitisation** — `$iface` and `$direction` stripped to `[a-zA-Z0-9_-]` before use in `awk` filters, file paths, and report output
- **Trap-based temp file cleanup** — `trap '...' EXIT INT TERM` ensures temp files are removed on clean exit, error, or signal; no files left behind if the script is killed mid-run
- **CI action pinned** — `ludeeus/action-shellcheck` pinned to commit SHA `00cae500` (v2.0.0) instead of `@master` to prevent supply-chain attacks via unreviewed upstream commits

---

## [2.0.2] — 2026-03-06

### Added

- **ShellCheck CI** — GitHub Actions workflow runs ShellCheck on all `.sh` files on every push and PR to `main`.

---

## [2.0.1] — 2026-03-06

### Fixed

- **Cron silent failure on CRLF scripts** — cron commands now use `sh /root/scripts/...` explicitly, bypassing the shebang. Previously, Windows CRLF line endings caused `#!/bin/sh\r` to fail silently at boot with no log output
- **pf table memory error at boot** — documented and set Firewall Maximum Table Entries to `600000`. The default limit caused `Cannot allocate memory` errors when loading the combined country + threat intel tables at boot, as pf temporarily holds old and new table data simultaneously during reloads

### Changed

- Troubleshooting content moved to a dedicated `TROUBLESHOOTING.md` with its own TOC; `GUIDE.md` links to it
- CRLF troubleshooting entry updated to cover both scripts and explain the shebang failure root cause
- Requirements updated: tested on pfSense 2.8.0; added table entries limit prerequisite

---

## [2.0.0] — 2026-02-28

### Added

- **IPv6 geo-blocking** — `update-all-countries.sh` now downloads IPv6 country ranges from ipdeny.com and saves them to `all_countries_v6_combined.txt` (85,000+ ranges, 250+ countries)
- **Per-interface + direction report sections** — each interface/direction pair (e.g. `pppoe4 Inbound`) gets its own section with protocol breakdown, top ports, top countries, and top source IPs
- **Country attribution** — MaxMind GeoLite2 Country database (bundled with pfBlockerNG-devel) is queried via `mmdblookup` for every IP in the report
- **Smart country context** — for LAN-side (outbound) blocks where the source IP is a private RFC 1918 address, the report shows the *destination* country (what foreign site your device tried to reach); for WAN inbound, it shows the *attacker's* source country
- **LAN device labeling** — private source IPs are labeled `[LAN]` instead of `[Private/Unknown]` in the Top Source IPs section
- **Port scanner detection** — a global section flags any external IP that probed 4 or more distinct destination ports within 24 hours, with the IP, country, and ports listed
- **Threat intel feed documentation** — GUIDE.md covers recommended pfBlockerNG feeds (PRI1, SCANNERS, PRI3) with Deny Both configuration
- **Shared webhook config** — both scripts load from `/usr/local/etc/geoblock-webhook.conf` so the webhook URL only needs to be set once
- **`.gitattributes`** — enforces LF line endings for `.sh` and `.md` files to prevent Windows CRLF from breaking FreeBSD shell scripts
- **`.gitignore`** — excludes OS noise, editor files, logs, temp files, and webhook config

### Fixed

- **Timestamp parsing** — pfSense 2.7+ uses RFC 5424 ISO 8601 timestamps (`2026-02-27T21:42:01+02:00`), not the old RFC 3164 format (`Feb 27 07:03:01`). The report script now parses `%Y-%m-%dT%H:%M:%S` correctly; previously all 24-hour windows returned empty, causing "No blocked connections" on every run
- **Wrong port in report** — destination port (`dst_port`) is now correctly extracted from filterlog CSV; previously the adjacent `src_port` (ephemeral) was used instead
- **BSD sed incompatibility** — replaced GNU-only `sed ':a;N;$!ba;s/\n/\\n/g'` with `awk '{printf "%s\\n", $0}'` for JSON newline encoding (FreeBSD sed printed "unused label" warnings)
- **IPv6 download** — ipdeny.com has no MD5SUM manifest for IPv6; changed to parse the directory listing HTML with `grep -o '[a-z][a-z]*-aggregated\.zone'`
- **DevSkim false positive** — `MD5SUM` as a remote filename (not used for crypto) now stored in a variable with an inline suppression comment

### Changed

- Documentation split into short `README.md` + detailed `GUIDE.md`
- Slack success notification now includes both IPv4 and IPv6 range counts

---

## [1.0.0] — 2025

### Added

- `update-all-countries.sh` — downloads IPv4 country IP ranges from ipdeny.com and writes a combined blocklist for pfBlockerNG
- `geo-block-report.sh` — parses pfSense firewall logs and sends a daily Slack summary of blocked connections
- Slack webhook integration with success/failure notifications
- Basic daily report: total blocks, top countries, top source IPs, top targeted ports
- README with quick-start instructions
