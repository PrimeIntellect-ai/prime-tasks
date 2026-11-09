#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle_etl.sh
#!/bin/bash
awk -F'|' -v OFS='|' '
{
    epoch = $1; event = $2; plate = $3; speed = $4;

    # Check deduplication window
    key = event "|" plate;
    is_dup = 0;
    if (key in last_seen) {
        diff = epoch - last_seen[key];
        # strictly within 3000ms inclusive -> if diff <= 3000 and diff >= -3000
        # Assuming stream is mostly chronological but absolute diff is safer
        if ((diff >= -3000 && diff <= 3000)) {
            is_dup = 1;
        }
    }

    if (!is_dup) {
        last_seen[key] = epoch;

        # Masking
        if (plate ~ /^[A-Z][A-Z][A-Z][0-9][0-9][0-9]$/) {
            plate = "***" substr(plate, 4, 3);
        }

        # Normalization
        sec = int(epoch / 1000);
        cmd = "date -u -d @" sec " +%Y-%m-%dT%H:%M:%SZ";
        cmd | getline iso_date;
        close(cmd);

        print iso_date, event, plate, speed;
    }
}'
EOF
    chmod +x /app/oracle_etl.sh

    cat << 'EOF' > /tmp/telemetry.srt
1
00:00:01,000 --> 00:00:02,000
1600000000000|SPEEDING|XYZ789|65

2
00:00:02,000 --> 00:00:03,000
1600000001500|SPEEDING|XYZ789|65

3
00:00:03,000 --> 00:00:04,000
1600000004000|BRAKE|ABC123|20

4
00:00:04,000 --> 00:00:05,000
1600000005000|BRAKE|A1B2C3|10
EOF
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -i /tmp/telemetry.srt -c:v libx264 -c:s mov_text -y /app/telemetry_stream.mp4 >/dev/null 2>&1

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
