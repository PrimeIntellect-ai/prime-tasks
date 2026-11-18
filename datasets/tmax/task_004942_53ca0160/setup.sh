#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace gawk
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/enricher
#!/bin/bash
# Mock binary for strace task
if ! exec 3< "/home/user/pipeline/.hidden_conf/rules.ini"; then
    echo "Error: Configuration missing" >&2
    exit 1
fi
exec 3<&-
echo "$1"
EOF
    chmod +x /home/user/pipeline/enricher

    cat << 'EOF' > /home/user/pipeline/aggregate.sh
#!/bin/bash
export TMPDIR=/home/user/pipeline/nonexistent_tmp

rm -f summary.csv

while read -r line; do
    /home/user/pipeline/enricher "$line" >> "$TMPDIR/enriched.log"
done < /home/user/pipeline/raw_events.log

awk '{print $1 "," $4}' "$TMPDIR/enriched.log" > /home/user/pipeline/summary.csv
EOF

    cat << 'EOF' > /home/user/pipeline/raw_events.log
2023-10-01 INFO 192.168.1.1 SUCCESS
2023-10-01 WARN 192.168.1.2 RETRY
CORRUPTED_LINE_NO_COLUMNS
2023-10-01 ERROR 192.168.1.3 FAILURE
DATA NULL BINARY \0\0\0
2023-10-02 INFO 192.168.1.4 SUCCESS
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
