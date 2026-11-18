#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_data/win_logs
    mkdir -p /home/user/legacy_data/csv_metrics

    echo -n "Warning: Memory high" | iconv -t UTF-16LE > /home/user/legacy_data/win_logs/SystemLog_A1.txt
    echo -n "Error: Disk space low" | iconv -t UTF-16LE > /home/user/legacy_data/win_logs/AppLog_B2.txt

    cat << 'EOF' > /home/user/legacy_data/csv_metrics/ServerStats_Jan.csv
cpu,memory,disk
80,90,50
60,70,80
EOF

    cat << 'EOF' > /home/user/legacy_data/csv_metrics/NetworkStats_Jan.csv
rx,tx,errors
1000,500,2
2000,800,0
EOF

    chmod -R 777 /home/user
