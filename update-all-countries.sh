#!/bin/sh
# pfSense Country Geo-Blocking Update Script with Error Handling

BASE_URL="https://www.ipdeny.com/ipblocks/data/aggregated"
OUTFILE="/var/db/pfblockerng/original/all_countries_combined.txt"
TMPFILE="/tmp/all_countries_temp.txt"
LOGFILE="/var/log/pfblockerng/all_countries.log"
WEBHOOK="YOUR_WEBHOOK_URL_HERE"  # Optional: Add Slack webhook URL

# Clear temp file
> $TMPFILE

# Log start
echo "$(date): Starting update..." >> $LOGFILE

# Download with error checking
curl -s "$BASE_URL/MD5SUM" | awk '{print $2}' | grep '\.zone$' | \
  while read zonefile; do
    curl -s "$BASE_URL/$zonefile" >> $TMPFILE
  done

# Check if download succeeded
if [ ! -s "$TMPFILE" ]; then
  ERROR_MSG="❌ pfSense: Country list update FAILED - No data downloaded"
  echo "$(date): ERROR - Download failed" >> $LOGFILE
  
  # Send failure notification
  if [ ! -z "$WEBHOOK" ]; then
    curl -X POST "$WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"$ERROR_MSG\"}"
  fi
  
  # Don't replace good file with empty file
  rm -f $TMPFILE
  exit 1
fi

# Verify reasonable IP count (should be >100,000)
IP_COUNT=$(wc -l < $TMPFILE)
if [ $IP_COUNT -lt 100000 ]; then
  ERROR_MSG="❌ pfSense: Country list update FAILED - Only $IP_COUNT IPs (expected >100k)"
  echo "$(date): ERROR - Incomplete download ($IP_COUNT IPs)" >> $LOGFILE
  
  if [ ! -z "$WEBHOOK" ]; then
    curl -X POST "$WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"$ERROR_MSG\"}"
  fi
  
  rm -f $TMPFILE
  exit 1
fi

# Create directory and move file
mkdir -p /var/db/pfblockerng/original
mv $TMPFILE $OUTFILE

# Final verification
FINAL_COUNT=$(wc -l < $OUTFILE)
echo "$(date): Updated - $FINAL_COUNT IPs" >> $LOGFILE

# Send success notification
if [ ! -z "$WEBHOOK" ]; then
  curl -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"✅ pfSense: Country list updated - $FINAL_COUNT IPs blocked\"}"
fi

echo "Update complete: $FINAL_COUNT IP ranges"
exit 0