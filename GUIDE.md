# Setup Guide

Full installation and configuration guide for pfSense Country Geo-Blocking.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Install Scripts](#install-scripts)
3. [Slack Webhook](#slack-webhook)
4. [Configure pfBlockerNG — IPv4](#configure-pfblockerng--ipv4)
5. [Configure pfBlockerNG — IPv6](#configure-pfblockerng--ipv6)
6. [Threat Intel Feeds](#threat-intel-feeds)
7. [Cron Jobs](#cron-jobs)
8. [Understanding the Daily Report](#understanding-the-daily-report)
9. [Whitelist a Country](#whitelist-a-country)
10. [Troubleshooting](#troubleshooting)

---

## Requirements

- pfSense 2.7+ (tested on 2.8.0)
- pfBlockerNG-devel installed (`System > Package Manager`)
- Internet connectivity for updates
- Slack workspace (optional, for notifications)

---

## Install Scripts

SSH into pfSense and run:

```bash
mkdir -p /root/scripts

curl -o /root/scripts/update-all-countries.sh \
  https://raw.githubusercontent.com/NX1X/pfsense-geo-block/main/update-all-countries.sh

curl -o /root/scripts/geo-block-report.sh \
  https://raw.githubusercontent.com/NX1X/pfsense-geo-block/main/geo-block-report.sh

chmod 750 /root/scripts/*.sh
```

> **Note:** If you edit scripts on Windows and SCP them to pfSense, run this after each transfer to strip Windows line endings:
> ```bash
> for f in update-all-countries.sh geo-block-report.sh; do
>   tr -d '\r' < /root/scripts/$f > /tmp/_lf.sh && mv /tmp/_lf.sh /root/scripts/$f && chmod 750 /root/scripts/$f
> done
> ```

---

## Slack Webhook

Both scripts share a single config file — set it once:

1. Go to [https://api.slack.com/apps](https://api.slack.com/apps) and create an app
2. Enable **Incoming Webhooks** and create a webhook URL for your channel
3. On pfSense:

```bash
echo 'WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"' \
  > /usr/local/etc/geoblock-webhook.conf
chmod 600 /usr/local/etc/geoblock-webhook.conf
```

If this file is missing or empty, scripts run silently without sending notifications.

---

## Configure pfBlockerNG — IPv4

### Run the initial update

```bash
sh /root/scripts/update-all-countries.sh
```

Verify it worked:

```bash
wc -l /var/db/pfblockerng/original/all_countries_v4_combined.txt
# Should show 175,000+
```

### Add the IPv4 rule in pfBlockerNG

**Firewall > pfBlockerNG > IP > IPv4 > Add**

| Field | Value |
|-------|-------|
| Name | `Block_All_Countries` |
| Action | `Deny Inbound` |
| State | `ON` |
| Update Frequency | `Never` (script handles updates) |

**IPv4 Source Definitions — Add:**

| Field | Value |
|-------|-------|
| Format | `Auto` |
| Source | `/var/db/pfblockerng/original/all_countries_v4_combined.txt` |

Save, then go to **Firewall > pfBlockerNG > Update** and click **Reload All**.

---

## Configure pfBlockerNG — IPv6

The update script also downloads IPv6 country ranges. After running it:

```bash
wc -l /var/db/pfblockerng/original/all_countries_v6_combined.txt
# Should show 85,000+
```

### Add the IPv6 rule

**Firewall > pfBlockerNG > IP > IPv6 > Add**

| Field | Value |
|-------|-------|
| Name | `Block_All_Countries_v6` |
| Action | `Deny Inbound` |
| State | `ON` |
| Update Frequency | `Never` |

**IPv6 Source Definitions — Add:**

| Field | Value |
|-------|-------|
| Format | `Auto` |
| Source | `/var/db/pfblockerng/original/all_countries_v6_combined.txt` |

Save and reload pfBlockerNG.

---

## Threat Intel Feeds

pfBlockerNG-devel includes a **Feeds** page with pre-configured threat intelligence lists.

**Firewall > pfBlockerNG > Feeds**

### Recommended feeds to enable

Click the `+` icon next to each feed to import it, then set **Action: Deny Both** (blocks inbound attacks AND outbound connections to known bad IPs).

#### PRI1 — High-quality, low false-positive feeds

| Feed Name | Alias | What it blocks |
|-----------|-------|----------------|
| Emerging Threats | `ET_Block` | Known malicious IPs |
| Emerging Threats | `ET_Comp` | Compromised servers |
| Spamhaus | `Spamhaus_Drop` | Hijacked/rogue networks (includes EDROP) |
| CINS Army | `CINS_army` | Scanners, brute force, botnets |
| Internet Storm Center | `ISC_Block` | Active threat IPs |

#### SCANNERS — IPs of known internet scanning services

| Feed Name | Alias | What it blocks |
|-----------|-------|----------------|
| ISC Shodan | `ISC_Shodan` | Shodan scanner IPs |
| ISC Rapid7 Sonar | `ISC_Rapid7Sonar` | Rapid7 research scanners |
| ISC ShadowServer | `ISC_Shadowserver` | ShadowServer scanners |
| ISC Errata Security | `ISC_Errata` | Masscan IPs |
| Maltrail | `Maltrail_Scanners_All` | All known scanning IPs |

#### PRI3 — Brute force and attack IPs

| Feed Name | Alias | What it blocks |
|-----------|-------|----------------|
| BlockList DE (SSH) | `BlockListDE_SSH` | SSH brute force IPs |
| BlockList DE (Brute) | `BlockListDE_Brute` | General brute force IPs |

### Why Deny Both?

- **Deny Inbound** — blocks attackers from reaching you
- **Deny Outbound** — blocks your devices from contacting known bad IPs (useful if a device is compromised and tries to call home to a C2 server)
- **Deny Both** — recommended for threat intel feeds

> The country geo-block rules use **Deny Inbound** only (you still need outbound internet access).

### After adding feeds

1. Go to **Firewall > pfBlockerNG > IP** and verify each feed's Action is set correctly
2. Go to **Firewall > pfBlockerNG > Update > Reload All**
3. Check the update log — feeds showing `0 Final` are fully covered by the country block list (those IPs were already blocked)

---

## Cron Jobs

**System > Cron > Add**

**Job 1 — Blocklist Update (7 AM daily):**

| Field | Value |
|-------|-------|
| Minute | `0` |
| Hour | `7` |
| Day / Month / Weekday | `*` |
| User | `root` |
| Command | `/root/scripts/update-all-countries.sh` |

**Job 2 — Daily Report (8 AM daily):**

| Field | Value |
|-------|-------|
| Minute | `0` |
| Hour | `8` |
| Day / Month / Weekday | `*` |
| User | `root` |
| Command | `/root/scripts/geo-block-report.sh` |

---

## Understanding the Daily Report

The report is split into sections:

### Overview

Total blocked connections and unique source IPs across all interfaces in the last 24 hours.

### Per-Interface Sections

Each interface and direction (Inbound/Outbound) gets its own section. Example:

```
🌐 wan0 — Inbound | 761 blocks
```

This is your WAN interface blocking external attackers.

```
🌐 igb0.20 — Inbound | 1722 blocks
```

This is a LAN VLAN — your devices are being blocked from reaching geo-blocked external IPs.

Each section shows:
- **Protocol** — TCP / UDP / ICMP breakdown
- **Top Targeted Ports** — destination ports being hit (SSH, HTTPS, RDP, etc.)
- **Top Countries** — for WAN inbound: where attackers are from. For LAN outbound: which foreign countries your devices tried to reach
- **Top Source IPs** — for WAN: attacker IPs with country. For LAN: your device IPs labeled `[LAN]`

### Port Scanners Detected

External IPs that probed 4 or more distinct destination ports within 24 hours — a strong indicator of port scanning behavior. Shows IP, country, and the ports they probed.

---

## Whitelist a Country

**Option 1 — Exclude from the download script:**

Edit `update-all-countries.sh` and add a `grep -v` filter:

```bash
# Example: exclude Israel (il) and United States (us)
curl -s "$BASE_URL_V4/$MANIFEST" | awk '{print $2}' | grep '\.zone$' | \
  grep -v 'il-aggregated\|us-aggregated' | \
  while read zonefile; do
```

**Option 2 — pfBlockerNG Permit rule:**

In pfBlockerNG, create a separate rule for the country with **Action: Permit Inbound** and place it above the block rule.

---

## Troubleshooting

### Report shows "No blocked connections"

Check that the firewall log has block entries:

```bash
grep ',block,' /var/log/filter.log | wc -l
```

If this returns 0, enable logging in your pfBlockerNG rule:
**Firewall > pfBlockerNG > IP > Edit rule > Logging: Enabled**

### Update script fails with "Syntax error: end of file"

Windows CRLF line endings. Fix with:

```bash
tr -d '\r' < /root/scripts/update-all-countries.sh > /tmp/_lf.sh && \
  mv /tmp/_lf.sh /root/scripts/update-all-countries.sh && \
  chmod 750 /root/scripts/update-all-countries.sh
```

### pfBlockerNG shows "No IPs found"

Verify the file exists and has content:

```bash
ls -lh /var/db/pfblockerng/original/all_countries_v4_combined.txt
head -3 /var/db/pfblockerng/original/all_countries_v4_combined.txt
```

### Feeds show 0 Final IPs

Normal — those IPs were already covered by the country block list and were deduplicated. The feeds add value when you whitelist specific countries.

### Country lookup shows blank

The GeoIP database path may differ. Check:

```bash
find /var/db/GeoIP /usr/local/share/GeoIP -name '*.mmdb' 2>/dev/null
```

---

## Monitoring

**Firewall > pfBlockerNG > Reports > IP Block Stats** — real-time block counters per list

**Firewall > pfBlockerNG > Logs** — detailed download and rule reload logs

**Dashboard Widget** — Add > pfBlockerNG widget for live overview
