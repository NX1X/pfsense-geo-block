#!/bin/sh
# pfSense Country Geo-Blocking Update Script — IPv4 + IPv6

BASE_URL_V4="https://www.ipdeny.com/ipblocks/data/aggregated"
BASE_URL_V6="https://www.ipdeny.com/ipv6/ipaddresses/aggregated"
OUTFILE_V4="/var/db/pfblockerng/original/all_countries_v4_combined.txt"
OUTFILE_V6="/var/db/pfblockerng/original/all_countries_v6_combined.txt"
TMPFILE_V4="/tmp/all_countries_v4_temp.txt"
TMPFILE_V6="/tmp/all_countries_v6_temp.txt"
LOGFILE="/var/log/pfblockerng/all_countries.log"

# Load shared Slack webhook config
WEBHOOK_CONF="/usr/local/etc/geoblock-webhook.conf"
WEBHOOK=""
if [ -f "$WEBHOOK_CONF" ]; then
  . "$WEBHOOK_CONF"
fi

mkdir -p /var/db/pfblockerng/original
echo "$(date): Starting IPv4 + IPv6 update..." >> $LOGFILE

MANIFEST="MD5SUM"  # DevSkim: ignore DS126858 - remote filename only, not used for crypto

# ── IPv4 ────────────────────────────────────────────────────────────────────
> $TMPFILE_V4
curl -s "$BASE_URL_V4/$MANIFEST" | awk '{print $2}' | grep '\.zone$' | \
  while read zonefile; do
    curl -s "$BASE_URL_V4/$zonefile" >> $TMPFILE_V4
  done

if [ ! -s "$TMPFILE_V4" ]; then
  MSG="❌ pfSense: IPv4 country list update FAILED - No data downloaded"
  echo "$(date): ERROR - IPv4 download failed" >> $LOGFILE
  [ -n "$WEBHOOK" ] && curl -s -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' -d "{\"text\":\"$MSG\"}"
  rm -f $TMPFILE_V4
  exit 1
fi

V4_COUNT=$(wc -l < $TMPFILE_V4 | tr -d ' ')
if [ $V4_COUNT -lt 100000 ]; then
  MSG="❌ pfSense: IPv4 country list update FAILED - Only $V4_COUNT ranges (expected >100k)"
  echo "$(date): ERROR - Incomplete IPv4 download ($V4_COUNT)" >> $LOGFILE
  [ -n "$WEBHOOK" ] && curl -s -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' -d "{\"text\":\"$MSG\"}"
  rm -f $TMPFILE_V4
  exit 1
fi

mv $TMPFILE_V4 $OUTFILE_V4
echo "$(date): IPv4 updated - $V4_COUNT ranges" >> $LOGFILE

# ── IPv6 ────────────────────────────────────────────────────────────────────
> $TMPFILE_V6
# Reuse the IPv4 manifest country codes to derive IPv6 zone URLs
curl -s "$BASE_URL_V4/$MANIFEST" | awk '{print $2}' | grep '\.zone$' | \
  while read zonefile; do
    cc="${zonefile%-aggregated.zone}"
    curl -s "$BASE_URL_V6/${cc}-aggregated.zone" >> $TMPFILE_V6
  done

if [ ! -s "$TMPFILE_V6" ]; then
  MSG="❌ pfSense: IPv6 country list update FAILED - No data downloaded"
  echo "$(date): ERROR - IPv6 download failed" >> $LOGFILE
  [ -n "$WEBHOOK" ] && curl -s -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' -d "{\"text\":\"$MSG\"}"
  rm -f $TMPFILE_V6
  # Don't exit — IPv4 already succeeded
else
  V6_COUNT=$(wc -l < $TMPFILE_V6 | tr -d ' ')
  if [ $V6_COUNT -lt 5000 ]; then
    MSG="❌ pfSense: IPv6 country list update FAILED - Only $V6_COUNT ranges (expected >5k)"
    echo "$(date): ERROR - Incomplete IPv6 download ($V6_COUNT)" >> $LOGFILE
    [ -n "$WEBHOOK" ] && curl -s -X POST "$WEBHOOK" \
      -H 'Content-Type: application/json' -d "{\"text\":\"$MSG\"}"
    rm -f $TMPFILE_V6
  else
    mv $TMPFILE_V6 $OUTFILE_V6
    echo "$(date): IPv6 updated - $V6_COUNT ranges" >> $LOGFILE
  fi
fi

# ── Notify ───────────────────────────────────────────────────────────────────
V6_FINAL=0
[ -f "$OUTFILE_V6" ] && V6_FINAL=$(wc -l < $OUTFILE_V6 | tr -d ' ')

if [ -n "$WEBHOOK" ]; then
  curl -s -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"✅ pfSense: Country lists updated — IPv4: $V4_COUNT ranges | IPv6: $V6_FINAL ranges\"}"
fi

echo "$(date): Update complete — v4: $V4_COUNT, v6: $V6_FINAL" >> $LOGFILE
exit 0
