#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/scripts
    mkdir -p /home/user/telemetry_logs

    # Create the buggy script
    cat << 'EOF' > /home/user/scripts/process.sh
#!/bin/bash
# Buggy telemetry processing script

LOG_FILE="/home/user/telemetry_logs/raw_data.log"

# Fails due to UTF-16LE encoding, and AWK loses precision
cat "$LOG_FILE" | jq -r '.bytes' | awk '{s+=$1} END {printf "%.0f\n", s}'
EOF
    chmod +x /home/user/scripts/process.sh

    # Generate the raw data in UTF-8 first
    TMP_DATA="/tmp/raw_data_utf8.log"
    rm -f $TMP_DATA

    # 41 entries of 10 = 410
    for i in $(seq 1 41); do
        printf '{"tx_id": "TXN_%03d", "bytes": 10}\n' "$i" >> $TMP_DATA
    done
    # Entry 42: large number > 2^53
    printf '{"tx_id": "TXN_042", "bytes": 9007199254744500}\n' >> $TMP_DATA
    # 12 entries of 10 = 120
    for i in $(seq 43 54); do
        printf '{"tx_id": "TXN_%03d", "bytes": 10}\n' "$i" >> $TMP_DATA
    done

    # Convert to UTF-16LE
    iconv -f UTF-8 -t UTF-16LE $TMP_DATA > /home/user/telemetry_logs/raw_data.log
    rm -f $TMP_DATA

    chmod -R 777 /home/user
