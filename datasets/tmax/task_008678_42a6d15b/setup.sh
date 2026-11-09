#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the simulated tcpdump ASCII capture
    cat << 'EOF' > /home/user/traffic.dump
12:00:01.000 IP 10.0.0.2.1234 > 10.0.0.1.8080: UDP, length 32
E.. ....  bm9kZS0xOjE3MDAwMDAwMDA6T0s=
12:00:06.000 IP 10.0.0.2.1234 > 10.0.0.1.8080: UDP, length 32
E.. ....  bm9kZS0xOjE3MDAwMDAwMDU6T0s=
12:00:16.000 IP 10.0.0.2.1234 > 10.0.0.1.8080: UDP, length 32
E.. ....  bm9kZS0xOjE3MDAwMDAwMTU6T0s=
12:00:10.000 IP 10.0.0.2.1234 > 10.0.0.1.8080: UDP, length 32
E.. ....  bm9kZS0xOjE3MDAwMDAwMTA6T0s=
12:00:46.000 IP 10.0.0.2.1234 > 10.0.0.1.8080: UDP, length 32
E.. ....  bm9kZS0xOjE3MDAwMDAwNDU6T0s=
12:00:50.000 IP 10.0.0.2.1234 > 10.0.0.1.8080: UDP, length 32
E.. ....  bm9kZS0xOjE3MDAwMDAwNTA6T0s=
EOF

    # Create the buggy script
    cat << 'EOF' > /home/user/monitor.sh
#!/bin/bash

DUMP_FILE=$1
if [ -z "$DUMP_FILE" ]; then
    echo "Usage: $0 <dump_file>"
    exit 1
fi

# Extract payloads, decode base64, filter for node-1, extract timestamp
# BUG 1: missing base64 padding handling or incorrect field extraction
# The payloads in dump might not be padded correctly if extracted raw, but here they are standard. 
# The bug here: awk '{print $3}' takes the payload, but base64 decoding fails or keeps newline.
declare -a TIMESTAMPS
while read -r b64_payload; do
    # BUG: uses wrong delimiter or index
    decoded=$(echo "$b64_payload" | base64 -d 2>/dev/null)
    if [[ "$decoded" == node-1* ]]; then
        ts=$(echo "$decoded" | cut -d':' -f2)
        TIMESTAMPS+=("$ts")
    fi
done < <(grep 'E\.\.' "$DUMP_FILE" | awk '{print $3}')

# BUG 4: Timestamps are not sorted, causing negative deltas in assertion
# Missing sort step here.

TOTAL_UPTIME=0
COUNT=${#TIMESTAMPS[@]}

# BUG 2 & 3: Off by one loop (<= instead of <), starts at 0 but compares with i+1
for (( i=0; i<=$COUNT; i++ )); do
    t1=${TIMESTAMPS[$i]}
    t2=${TIMESTAMPS[$((i+1))]}

    if [ -z "$t2" ]; then
        continue
    fi

    delta=$((t2 - t1))

    # ASSERTION: time must always move forward
    if [ "$delta" -lt 0 ]; then
        echo "ASSERTION FAILED: Negative time delta $delta"
        exit 1
    fi

    if [ "$delta" -le 20 ]; then
        TOTAL_UPTIME=$((TOTAL_UPTIME + delta))
    fi
done

echo "$TOTAL_UPTIME"
EOF

    chmod +x /home/user/monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
