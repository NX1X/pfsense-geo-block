# pfSense Country-Based Geo-Blocking with pfBlockerNG

![Visitors](https://visitor-badge.laobi.icu/badge?page_id=NX1X.pfsense-geo-block)

[![GitHub](https://img.shields.io/badge/GitHub-Repository-black)](https://github.com/NX1X/pfsense-geo-block)
[![Setup Guide](https://img.shields.io/badge/Docs-Setup%20Guide-blue)](GUIDE.md)
[![Changelog](https://img.shields.io/badge/Docs-Changelog-blue)](CHANGELOG.md)
[![Blog](https://img.shields.io/badge/Blog-Articles-green)](https://blog.nx1xlab.dev/)
[![Support](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-yellow)](https://buymeacoffee.com/nx1x)
[![Website](https://img.shields.io/badge/Website-nx1xlab.dev-purple)](https://www.nx1xlab.dev/)

Block all countries (IPv4 + IPv6) using pfBlockerNG, with daily Slack reports showing per-interface breakdowns, country attribution, and port scanner detection.

## Features

- Blocks 175,000+ IPv4 ranges and 85,000+ IPv6 ranges from 250+ countries
- Daily Slack report: per-interface/direction breakdown, top countries, port scanners
- Country lookup via MaxMind GeoLite2 (bundled with pfBlockerNG)
- Smart context: shows destination country for outbound LAN blocks, source country for inbound WAN attacks
- Port scanner detection: flags external IPs probing 4+ distinct ports
- Works alongside pfBlockerNG threat intel feeds (CINS, Emerging Threats, BlockListDE, ISC)
- Slack notifications on update success or failure

## Scripts

| Script | Purpose | Default Schedule |
|--------|---------|-----------------|
| `update-all-countries.sh` | Downloads IPv4 + IPv6 country IP lists and updates the blocklist | Daily at 7 AM |
| `geo-block-report.sh` | Parses firewall logs and sends a daily block summary to Slack | Daily at 8 AM |

## Quick Start

```bash
# 1. Download scripts
mkdir -p /root/scripts
curl -o /root/scripts/update-all-countries.sh https://raw.githubusercontent.com/NX1X/pfsense-geo-block/main/update-all-countries.sh
curl -o /root/scripts/geo-block-report.sh https://raw.githubusercontent.com/NX1X/pfsense-geo-block/main/geo-block-report.sh
chmod 750 /root/scripts/*.sh

# 2. Set up Slack webhook (optional)
echo 'WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"' > /usr/local/etc/geoblock-webhook.conf
chmod 600 /usr/local/etc/geoblock-webhook.conf

# 3. Run initial update
sh /root/scripts/update-all-countries.sh

# 4. Configure pfBlockerNG — see GUIDE.md

# 5. Set up cron jobs (System > Cron in pfSense UI)
#    7 AM → /root/scripts/update-all-countries.sh
#    8 AM → /root/scripts/geo-block-report.sh
```

## Documentation

- **[Setup Guide](GUIDE.md)** — full installation, pfBlockerNG IPv4/IPv6 rules, threat feeds, cron setup, troubleshooting
- **[Changelog](CHANGELOG.md)** — version history

## Requirements

- pfSense 2.7+ (tested on 2.8.0)
- pfBlockerNG-devel installed
- Internet connectivity for updates

## License

MIT — Free to use and modify

## Credits

- [IPDeny.com](https://www.ipdeny.com/) for country IP data
- pfBlockerNG team
- MaxMind for GeoLite2 database

**Last Updated:** February 2026
