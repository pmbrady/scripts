#!/bin/bash
# /home/docker/record.sh
# Usage: record.sh <start_hour> <start_minute> <day_of_month> <duration> <filename> <channel_number>
# Example: record.sh 22 30 11 90m arsenal 148

set -u
set -o pipefail

if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <start_hour> <start_minute> <day_of_month> <duration> <filename> <channel_number>"
    exit 1
fi

START_HOUR=$1
START_MINUTE=$2
DAY_OF_MONTH=$3
DURATION=$4   # supports "90m", "2h", "1d", or plain number (hours)
FILENAME=$5
CHANNEL=$6

# --- IPTV credentials ---
# --- IPTV credentials from environment ---
if [ -z "${IPTVUSER:-}" ] || [ -z "${IPTVPASS:-}" ]; then
    echo "ERROR: IPTVUSER or IPTVPASS not set. Export them before running:"
    echo "  export IPTVUSER=youruser"
    echo "  export IPTVPASS=yourpass"
    exit 1
fi

IPTV_URL="httpstream://http://ension425.com:80/live/${IPTVUSER}/${IPTVPASS}/${CHANNEL}.ts"

BASE_DIR="/home/docker/plex/replays"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$BASE_DIR" "$LOG_DIR"

YEAR=$(date +%Y)
MONTH=$(date +%m)
START_DATE="$YEAR-$MONTH-$DAY_OF_MONTH $START_HOUR:$START_MINUTE:00"

# Convert start date to epoch
if ! START_TIMESTAMP=$(date -d "$START_DATE" +%s 2>/dev/null); then
  echo "Invalid start date: $START_DATE"
  exit 1
fi

# Parse duration into seconds
case "$DURATION" in
    *h) SECS=$(( ${DURATION%h} * 3600 )) ;;
    *m) SECS=$(( ${DURATION%m} * 60 )) ;;
    *d) SECS=$(( ${DURATION%d} * 86400 )) ;;
    *) 
        if [[ "$DURATION" =~ ^[0-9]+$ ]]; then
            SECS=$(( DURATION * 3600 ))
        else
            echo "Invalid duration: $DURATION (use 90m, 2h, 1d, or number of hours)"
            exit 1
        fi
        ;;
esac

END_TIMESTAMP=$(( START_TIMESTAMP + SECS ))
START_HUMAN=$(date -d @$START_TIMESTAMP "+%Y-%m-%d %H:%M:%S")
END_HUMAN=$(date -d @$END_TIMESTAMP "+%Y-%m-%d %H:%M:%S")

echo "Scheduling recording"
echo "Start : $START_HUMAN ($START_TIMESTAMP)"
echo "End   : $END_HUMAN ($END_TIMESTAMP)"
echo "Channel: $CHANNEL"
echo "Base filename: $FILENAME"

# Generate recording script
SCRIPT_PATH="$BASE_DIR/record_$FILENAME.sh"
LOGFILE="$LOG_DIR/${FILENAME}_$(date +%Y%m%d_%H%M%S).log"

# Determine next available MP4 filename to avoid overwriting
i=0
while true; do
    if [ $i -eq 0 ]; then
        OUTFILE="$BASE_DIR/${FILENAME}.mp4"
    else
        OUTFILE="$BASE_DIR/${FILENAME}-$i.mp4"
    fi
    [ ! -f "$OUTFILE" ] && break
    i=$((i + 1))
done

cat <<'EOF' > "$SCRIPT_PATH"
#!/bin/bash
# Auto-generated recording script (MP4 direct, incremental filenames)

IPTV_URL="__IPTV_URL__"
OUTFILE="__OUTFILE__"
LOGFILE="__LOGFILE__"
END_TIMESTAMP=__END_TIMESTAMP__
CHANNEL="__CHANNEL__"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "Recording started for channel: $CHANNEL"
log "Output: $OUTFILE"

# Loop until end time
set -o pipefail

while [ $(date +%s) -lt $END_TIMESTAMP ]; do
    DURATION_LEFT=$(( END_TIMESTAMP - $(date +%s) ))
    if [ $DURATION_LEFT -le 0 ]; then
        log "Reached end time, stopping recording"
        break
    fi

    timeout $DURATION_LEFT streamlink --stdout "$IPTV_URL" best \
        | ffmpeg -y -loglevel error -i - -c copy -f mp4 "$OUTFILE"

    # capture exit codes of both pipeline components
    STREAMLINK_EXIT=${PIPESTATUS[0]:-127}
    FFMPEG_EXIT=${PIPESTATUS[1]:-127}
    log "streamlink exit: $STREAMLINK_EXIT, ffmpeg exit: $FFMPEG_EXIT"

    # consider it a success only if both are 0
    if [ $STREAMLINK_EXIT -ne 0 ] || [ $FFMPEG_EXIT -ne 0 ]; then
        log "Error during recording, retrying in 10 seconds..."
        sleep 10
        continue
    fi

    log "Recording finished successfully"
    break
done

log "Recording completed: $OUTFILE"
EOF

# Replace placeholders
sed -i \
    -e "s|__IPTV_URL__|$IPTV_URL|g" \
    -e "s|__OUTFILE__|$OUTFILE|g" \
    -e "s|__LOGFILE__|$LOGFILE|g" \
    -e "s|__END_TIMESTAMP__|$END_TIMESTAMP|g" \
    -e "s|__CHANNEL__|$CHANNEL|g" \
    "$SCRIPT_PATH"

chmod +x "$SCRIPT_PATH"

# Schedule with cron
TMP_CRON=$(mktemp)
crontab -l 2>/dev/null | grep -v -F "$SCRIPT_PATH" > "$TMP_CRON" || true
echo "$START_MINUTE $START_HOUR $DAY_OF_MONTH * * /bin/bash \"$SCRIPT_PATH\" >> \"$LOGFILE\" 2>&1" >> "$TMP_CRON"
crontab "$TMP_CRON"
rm -f "$TMP_CRON"

echo "Recording scheduled:"
echo " - Script: $SCRIPT_PATH"
echo " - Log: $LOGFILE"
echo " - MP4 file: $OUTFILE"

