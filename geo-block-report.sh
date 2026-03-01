#!/bin/sh
# pfSense Geo-Block Daily Summary Report to Slack
# Parses pfSense filter logs and sends per-interface/direction summary with country info
# Schedule via cron (e.g., daily at 8 AM)

# Load shared Slack webhook config
WEBHOOK_CONF="/usr/local/etc/geoblock-webhook.conf"
WEBHOOK=""
if [ -f "$WEBHOOK_CONF" ]; then
  . "$WEBHOOK_CONF"
fi
LOGFILE="/var/log/filter.log"
REPORT_LOG="/var/log/pfblockerng/geo_report.log"
HOURS=24

echo "$(date): Generating geo-block report..." >> "$REPORT_LOG"

NOW=$(date +%s)
CUTOFF=$((NOW - HOURS * 3600))
TMPFILE="/tmp/geo_block_report_tmp.txt"
> "$TMPFILE"

# Parse log (RFC 5424 ISO 8601 timestamps, pfSense 2.7+)
# Filterlog CSV fields (comma-split): $5=interface, $7=action, $8=direction
if [ -f "$LOGFILE" ]; then
  grep ',block,' "$LOGFILE" 2>/dev/null | while IFS= read -r line; do
    # Field 2 is the ISO 8601 timestamp: 2026-02-27T21:42:01.346878+02:00
    LOG_TS=$(echo "$line" | awk '{print $2}' | cut -c1-19)
    LOG_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$LOG_TS" +%s 2>/dev/null)
    if [ -n "$LOG_EPOCH" ] && [ "$LOG_EPOCH" -ge "$CUTOFF" ]; then
      echo "$line" >> "$TMPFILE"
    fi
  done
fi

TOTAL_BLOCKS=$(wc -l < "$TMPFILE" | tr -d ' ')

if [ "$TOTAL_BLOCKS" -eq 0 ]; then
  echo "$(date): No blocked connections in the last ${HOURS}h" >> "$REPORT_LOG"
  if [ -n "$WEBHOOK" ]; then
    curl -s -X POST "$WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"📊 *pfSense Geo-Block Daily Report*\nNo blocked connections in the last ${HOURS} hours.\"}"
  fi
  rm -f "$TMPFILE"
  exit 0
fi

# Locate MaxMind GeoLite2 Country database installed by pfBlockerNG
GEOIP_DB=""
if command -v mmdblookup > /dev/null 2>&1; then
  for _db in /var/db/GeoIP/GeoLite2-Country.mmdb /usr/local/share/GeoIP/GeoLite2-Country.mmdb; do
    [ -f "$_db" ] && GEOIP_DB="$_db" && break
  done
fi

# Pre-compute IP -> country mapping for both source AND destination IPs
# (destination is needed when source is a private/LAN IP)
IP_COUNTRY_FILE="/tmp/geo_ip_countries.txt"
if [ -n "$GEOIP_DB" ]; then
  awk -F',' '{
    count = 0
    for(i=1;i<=NF;i++) {
      if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
        print $i
        count++
        if(count == 2) break
      }
    }
  }' "$TMPFILE" | sort -u | while read _ip; do
    _country=$(mmdblookup --file "$GEOIP_DB" --ip "$_ip" country names en 2>/dev/null | \
      grep -o '"[^"]*"' | head -1 | tr -d '"')
    [ -z "$_country" ] && _country=""
    printf '%s\t%s\n' "$_ip" "$_country"
  done > "$IP_COUNTRY_FILE"
else
  > "$IP_COUNTRY_FILE"
fi

# Returns 0 (true) if IP is RFC 1918 / CGNAT / loopback / link-local
is_private_ip() {
  case "$1" in
    10.*|192.168.*|127.*|169.254.*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
  esac
  return 1
}

# Format well-known port numbers
format_port() {
  case $1 in
    22) echo "$1 (SSH)" ;; 23) echo "$1 (Telnet)" ;;
    25) echo "$1 (SMTP)" ;; 53) echo "$1 (DNS)" ;;
    80) echo "$1 (HTTP)" ;; 443) echo "$1 (HTTPS)" ;;
    445) echo "$1 (SMB)" ;; 3389) echo "$1 (RDP)" ;;
    1900) echo "$1 (UPnP)" ;; 5351) echo "$1 (NAT-PMP)" ;;
    8080) echo "$1 (HTTP-Alt)" ;;
    *) echo "$1" ;;
  esac
}

REPORT_TMPFILE="/tmp/geo_report_msg.txt"
> "$REPORT_TMPFILE"

UNIQUE_IPS=$(awk -F',' '{
  for(i=1;i<=NF;i++) {
    if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; break }
  }
}' "$TMPFILE" | sort -u | wc -l | tr -d ' ')

# Header
{
  echo "📊 *pfSense Geo-Block Daily Report*"
  echo "Period: Last ${HOURS} hours | $(date '+%Y-%m-%d %H:%M')"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📈 *Overview*"
  echo "• Total blocked connections: *${TOTAL_BLOCKS}*"
  echo "• Unique source IPs: *${UNIQUE_IPS}*"
  [ -z "$GEOIP_DB" ] && echo "• GeoIP database not found — countries unavailable"
  echo ""
} >> "$REPORT_TMPFILE"

# Get interface+direction pairs sorted by total block count (highest first)
IFACE_DIRS=$(awk -F',' '{print $5 "|" $8}' "$TMPFILE" | sort | uniq -c | sort -rn | awk '{print $2}')

# Awk snippet shared across sections: outputs the "effective" IP for geo-lookup.
# If source IP is private/LAN, use destination IP (what they're connecting to).
# If source IP is public, use source IP (the attacker).
AWK_EFFECTIVE_IP='
function is_private(ip,    p, n, o1, o2) {
  n = split(ip, p, ".")
  if (n != 4) return 1
  o1 = p[1]+0; o2 = p[2]+0
  if (o1 == 10) return 1
  if (o1 == 192 && o2 == 168) return 1
  if (o1 == 172 && o2 >= 16 && o2 <= 31) return 1
  if (o1 == 100 && o2 >= 64 && o2 <= 127) return 1
  if (o1 == 127 || o1 == 169) return 1
  return 0
}
{
  src = ""; dst = ""; cnt = 0
  for(i=1;i<=NF;i++) {
    if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
      cnt++
      if(cnt == 1) src = $i
      if(cnt == 2) { dst = $i; break }
    }
  }
  if (src != "") {
    if (is_private(src) && dst != "") print dst
    else print src
  }
}'

# Generate a section for each interface+direction combination
echo "$IFACE_DIRS" | while IFS='|' read iface direction; do
  [ -z "$iface" ] && continue

  SECTION_FILE="/tmp/geo_section_${iface}_${direction}.txt"
  awk -F',' -v iface="$iface" -v dir="$direction" \
    '$5 == iface && $8 == dir' "$TMPFILE" > "$SECTION_FILE"

  SEC_COUNT=$(wc -l < "$SECTION_FILE" | tr -d ' ')
  [ "$SEC_COUNT" -eq 0 ] && rm -f "$SECTION_FILE" && continue

  [ "$direction" = "in" ] && DIR_LABEL="Inbound" || DIR_LABEL="Outbound"

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 *${iface}* — ${DIR_LABEL} | *${SEC_COUNT}* blocks"
    echo ""

    # Protocol breakdown
    echo "🔒 *Protocol*"
    awk -F',' '{
      for(i=1;i<=NF;i++) {
        if($i=="tcp"||$i=="udp"||$i=="icmp"||$i=="igmp") { print $i; break }
      }
    }' "$SECTION_FILE" | sort | uniq -c | sort -rn | \
    while read _count _proto; do echo "• ${_proto}: ${_count}"; done
    echo ""

    # Top destination ports
    echo "🚪 *Top Targeted Ports*"
    awk -F',' '{
      found_ip=0
      for(i=1;i<=NF;i++) {
        if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
          found_ip++
          if(found_ip==2) {
            port=$(i+2)
            if(port ~ /^[0-9]+$/ && port+0 > 0 && port+0 < 65536) print port
            break
          }
        }
      }
    }' "$SECTION_FILE" | sort | uniq -c | sort -rn | head -5 | \
    while read _count _port; do
      echo "• $(format_port "$_port") — ${_count} hits"
    done
    echo ""

    # Top countries:
    # - private source IP → country of DESTINATION (what LAN devices are reaching)
    # - public source IP  → country of SOURCE (where the attacker is from)
    echo "🗺️ *Top Countries*"
    awk -F',' "$AWK_EFFECTIVE_IP" "$SECTION_FILE" | sort | uniq -c | \
    while read _count _ip; do
      _country=$(awk -F'\t' -v ip="$_ip" '$1==ip{print $2; exit}' "$IP_COUNTRY_FILE")
      [ -z "$_country" ] && _country="Unknown"
      printf '%s\t%d\n' "$_country" "$_count"
    done | awk -F'\t' '{sum[$1]+=$2} END{for(c in sum) printf "%d\t%s\n", sum[c], c}' | \
    sort -rn | head -5 | \
    while read _count _country; do
      echo "• ${_country}: ${_count} blocks"
    done
    echo ""

    # Top source IPs:
    # - private → label [LAN], public → label [Country]
    echo "🎯 *Top Source IPs*"
    awk -F',' '{
      for(i=1;i<=NF;i++) {
        if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; break }
      }
    }' "$SECTION_FILE" | sort | uniq -c | sort -rn | head -10 | \
    while read _count _ip; do
      if is_private_ip "$_ip"; then
        echo "• \`${_ip}\` [LAN] — ${_count} blocks"
      else
        _country=$(awk -F'\t' -v ip="$_ip" '$1==ip{print $2; exit}' "$IP_COUNTRY_FILE")
        [ -z "$_country" ] && _country="—"
        echo "• \`${_ip}\` [${_country}] — ${_count} blocks"
      fi
    done
    echo ""

  } >> "$REPORT_TMPFILE"

  rm -f "$SECTION_FILE"
done

# --- Global: Port Scanner Detection ---
# An external IP probing 4+ distinct destination ports in 24h = likely scanning
SCANNER_RESULTS=$(awk -F',' '
function is_private(ip,    p,n,o1,o2) {
  n=split(ip,p,".")
  if(n!=4) return 1
  o1=p[1]+0; o2=p[2]+0
  if(o1==10||o1==127||o1==169) return 1
  if(o1==192&&o2==168) return 1
  if(o1==172&&o2>=16&&o2<=31) return 1
  if(o1==100&&o2>=64&&o2<=127) return 1
  return 0
}
{
  src=""; cnt=0; di=0
  for(i=1;i<=NF;i++) {
    if($i~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
      cnt++
      if(cnt==1) src=$i
      if(cnt==2) { di=i; break }
    }
  }
  if(src!=""&&!is_private(src)&&di>0) {
    port=$(di+2)
    if(port~/^[0-9]+$/&&port+0>0&&port+0<65536) print src "|" port
  }
}' "$TMPFILE" | sort -u | \
awk -F'|' '{
  cnt[$1]++
  if(cnt[$1]<=10) pl[$1]=(pl[$1]==""?$2:pl[$1]","$2)
} END {
  for(ip in cnt) if(cnt[ip]>=4) printf "%d %s [%s]\n", cnt[ip], ip, pl[ip]
}' | sort -rn | head -10)

{
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 *Port Scanners Detected* (4+ distinct ports probed)"
  echo ""
  if [ -z "$SCANNER_RESULTS" ]; then
    echo "• None detected in the last ${HOURS} hours"
  else
    echo "$SCANNER_RESULTS" | while read _portcount _ip _ports; do
      _country=$(awk -F'\t' -v ip="$_ip" '$1==ip{print $2; exit}' "$IP_COUNTRY_FILE")
      [ -z "$_country" ] && _country="—"
      echo "• \`${_ip}\` [${_country}] — ${_portcount} ports: ${_ports}"
    done
  fi
  echo ""
} >> "$REPORT_TMPFILE"

# Encode newlines for JSON using awk (BSD sed compatible)
REPORT_TEXT=$(awk '{printf "%s\\n", $0}' "$REPORT_TMPFILE" | sed 's/"/\\"/g')

if [ -n "$WEBHOOK" ]; then
  curl -s -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"${REPORT_TEXT}\"}"
  echo "$(date): Report sent (${TOTAL_BLOCKS} blocks, ${UNIQUE_IPS} unique IPs)" >> "$REPORT_LOG"
else
  echo "$(date): Webhook not configured, printing report:" >> "$REPORT_LOG"
  cat "$REPORT_TMPFILE" >> "$REPORT_LOG"
fi

rm -f "$TMPFILE" "$REPORT_TMPFILE" "$IP_COUNTRY_FILE"
echo "$(date): Report complete" >> "$REPORT_LOG"
exit 0
