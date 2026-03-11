# Troubleshooting

---

## Table of Contents

1. [Cron job not running / no log entries after reboot](#cron-job-not-running--no-log-entries-after-reboot)
2. [Update script fails with "Syntax error: end of file"](#update-script-fails-with-syntax-error-end-of-file)
3. [Dashboard shows "Cannot allocate memory" on pfB table at boot](#dashboard-shows-cannot-allocate-memory-on-pfb-table-at-boot)
4. [Report shows "No blocked connections"](#report-shows-no-blocked-connections)
5. [pfBlockerNG shows "No IPs found"](#pfblockerng-shows-no-ips-found)
6. [Feeds show 0 Final IPs](#feeds-show-0-final-ips)
7. [Country lookup shows blank](#country-lookup-shows-blank)

---

### Cron job not running / no log entries after reboot

If `geo_report.log` has no entries for expected run times, the script likely has Windows CRLF line endings. When cron executes a script directly (via shebang), `#!/bin/sh\r` fails silently — no log, no error. Fix:

```bash
for f in update-all-countries.sh geo-block-report.sh; do
  sed -i '' 's/\r//' /root/scripts/$f
done
```

**Prevent this permanently — use binary transfer when copying scripts to pfSense:**

- **Windows PowerShell / Command Prompt (recommended):** Use the built-in `scp` — it always transfers in binary mode:
  ```powershell
  scp update-all-countries.sh geo-block-report.sh admin@pfsense:/root/scripts/
  ```
- **WinSCP:** Options → Preferences → Transfer → Default → Transfer mode → **Binary**
- **Any other tool:** ensure it is set to binary / raw mode, not "text" or "ASCII" mode

> The repository's `.gitattributes` enforces LF line endings in git, so files checked out locally are always correct. CRLF only appears if your transfer tool converts line endings during upload.

To prevent silent failures in cron regardless, use `sh` explicitly — this bypasses the shebang so the script starts and logs even if CRLF sneaks in. Both cron commands in the setup guide already use this form:

```
sh /root/scripts/update-all-countries.sh
sh /root/scripts/geo-block-report.sh
```

---

### Update script fails with "Syntax error: end of file"

Same CRLF issue as above. Run the fix and switch to binary transfer mode.

---

### Dashboard shows "Cannot allocate memory" on pfB table at boot

The combined country + threat intel lists exceed pf's default table-entries limit. During boot or rule reloads, pf temporarily holds old and new table data simultaneously, doubling the peak memory needed.

Fix: **System > Advanced > Firewall & NAT > Firewall Maximum Table Entries → `600000`**

Then reload: **Firewall > pfBlockerNG > Update > Force > Reload All**

Verify the current limit and usage:

```bash
pfctl -sm | grep table
wc -l /var/db/aliastables/*.txt | tail -1
```

---

### Report shows "No blocked connections"

Check that the firewall log has block entries:

```bash
grep ',block,' /var/log/filter.log | wc -l
```

If this returns 0, enable logging in your pfBlockerNG rule:
**Firewall > pfBlockerNG > IP > Edit rule > Logging: Enabled**

---

### pfBlockerNG shows "No IPs found"

Verify the file exists and has content:

```bash
ls -lh /var/db/pfblockerng/original/all_countries_v4_combined.txt
head -3 /var/db/pfblockerng/original/all_countries_v4_combined.txt
```

---

### Feeds show 0 Final IPs

Normal — those IPs were already covered by the country block list and were deduplicated. The feeds add value when you whitelist specific countries.

---

### Country lookup shows blank

The GeoIP database path may differ. Check:

```bash
find /var/db/GeoIP /usr/local/share/GeoIP -name '*.mmdb' 2>/dev/null
```
