# pfSense Country-Based Geo-Blocking with pfBlockerNG

![Visitors](https://visitor-badge.laobi.icu/badge?page_id=NX1X.pfsense-geo-block)


Automatically block ALL countries using pfBlockerNG with daily updates and Slack notifications.

## Features

- ✅ Blocks 174,000+ IP ranges from 250+ countries
- ✅ Daily automatic updates at 3 AM
- ✅ Slack notifications on updates
- ✅ Uses IPDeny aggregated country lists
- ✅ ~2.6MB combined blocklist
- ✅ Allows outbound traffic (internet access maintained)

## Requirements

- pfSense 2.8+ (Might work on older versions - not tested)
- pfBlockerNG package installed
- 50MB free disk space
- Internet connectivity for updates

## Quick Start

### 1. Install the Update Script
```bash
# Download and install
curl -o /usr/local/bin/update-all-countries.sh https://raw.githubusercontent.com/NX1X/pfsense-geo-block/main/update-all-countries.sh

# Set permissions
chmod 750 /usr/local/bin/update-all-countries.sh

# Edit to add your Slack webhook (optional)
nano /usr/local/bin/update-all-countries.sh
```

### 2. Run Initial Update
```bash
sh /usr/local/bin/update-all-countries.sh
```
### Check logs
tail -3 /var/log/pfblockerng/all_countries.log


Verify file created:
```bash
wc -l /var/db/pfblockerng/original/all_countries_combined.txt
# Should show ~174,206 lines
```

### 3. Configure pfBlockerNG

**Go to: Firewall > pfBlockerNG > IP > IPv4**

- Click **"+ Add"**
- **Name:** `Block_All_Countries`
- **Action:** `Deny Inbound`
- **State:** `ON`
- **Update Frequency:** `Never` (script handles updates)

**IPv4 Source Definitions:**
- Click **"+ Add"**
- **Format:** `Auto`
- **Source:** `/var/db/pfblockerng/original/all_countries_combined.txt`

**Click Save**

### 4. Apply Configuration

**Go to: Firewall > pfBlockerNG > Update**

Click **"Reload"**

Wait for completion. Verify:
```
✅ allcountries_v4: 173,448 IPs loaded
✅ Total blocking: 190,000+ IPs
```

### 5. Set Up Daily Cron Job

**Go to: System > Cron**

Click **"+ Add"**

- **Minute:** `0`
- **Hour:** `3`
- **Day:** `*`
- **Month:** `*`
- **Weekday:** `*`
- **User:** `root`
- **Command:** `/usr/local/bin/update-all-countries.sh`

Click **Save**

## Configuration

### Slack Notifications (Optional)

**Create a new app in slack: [https://api.slack.com/apps]**
**Go to "Incoming Webhooks" and create a webhook URL"**
**Copy the Webhook URL and paste in the script**

Edit the script:
```bash
nano /usr/local/bin/update-all-countries.sh
```

Update webhook URL:
```sh
WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Custom Update Schedule

Modify cron job timing as needed. Default is 3 AM daily.

### Whitelist Your Country

If you need to allow specific countries:

**Option 1:** Edit the script to exclude countries
```sh
# In the script, filter out specific countries:
curl -s "$BASE_URL/MD5SUM" | awk '{print $2}' | grep '\.zone$' | grep -v 'us-aggregated\|il-aggregated' | \
```

**Option 2:** Create separate pfBlockerNG rule with "Permit" action for your country

## Monitoring

### View Blocked Traffic

**Go to: Firewall > pfBlockerNG > Reports > IP Block Stats**

Shows real-time blocks with:
- Source IP and country
- Timestamp
- Blocked rule

### Dashboard Widget

**Go to: Dashboard**
- Click **"+ Add Widget"**
- Select **pfBlockerNG**

### Reports


## Troubleshooting

### Script Not Creating File

Check permissions:
```bash
ls -la /usr/local/bin/update-all-countries.sh
# Should be: -rwxr-x--- root wheel
```

Run manually to see errors:
```bash
sh -x /usr/local/bin/update-all-countries.sh
```

### pfBlockerNG Shows "No IPs found"

Verify file exists and has content:
```bash
ls -lh /var/db/pfblockerng/original/all_countries_combined.txt
head -5 /var/db/pfblockerng/original/all_countries_combined.txt
```

Check source path in rule (must be exact):
```
/var/db/pfblockerng/original/all_countries_combined.txt
```

## Performance Impact

- **CPU:** Minimal (<1% during update)
- **RAM:** ~50MB during update
- **Disk:** 2.6MB for blocklist
- **Network:** ~5MB download during update
- **Update Time:** 1-2 minutes

## Data Source

- **Provider:** [IPDeny.com](https://www.ipdeny.com/)
- **Update Frequency:** Daily
- **Format:** Aggregated CIDR blocks per country
- **License:** Free for personal and commercial use

## Security Notes

⚠️ **Important:**
- This blocks ALL inbound traffic from all countries
- Outbound traffic (your browsing) still works
- VPN traffic may be affected
- Some CDNs use IPs from multiple countries

**Whitelist critical services:**
- Your VPN provider IPs
- Business partner IPs
- Monitoring services

## FAQ

**Q: Will this block my internet access?**
A: No, it only blocks inbound connections. You can still browse normally.

**Q: How do I allow one specific country?**
A: Create a separate pfBlockerNG rule with "Permit Inbound" for that country above this rule.

**Q: Can I block continents instead of all countries?**
A: Yes, manually specify continent country codes in the script filter.

**Q: Does this work with IPv6?**
A: This script handles IPv4 only. IPv6 requires separate configuration.

**Q: How much does this protect me?**
A: Blocks ~90% of automated attacks. Use with other security measures.

## Contributing

Pull requests welcome! Please:
1. Test thoroughly on pfSense 2.7+/2.8+
2. Update documentation
3. Follow existing code style

## License

MIT License - Free to use and modify

## Credits

- IPDeny.com for country IP data
- pfBlockerNG team for the excellent package
- pfSense community

## Support

- Issues: GitHub Issues
- pfSense Forum: [pfBlockerNG section](https://forum.netgate.com/category/56/pfblockerng)
- Documentation: [pfBlockerNG Docs](https://docs.netgate.com/pfsense/en/latest/packages/pfblocker.html)

---

**Last Updated:** November 2025

**Tested On:** pfSense 2.8.1



