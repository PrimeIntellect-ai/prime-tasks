#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron gawk sed
    pip3 install pytest

    mkdir -p /home/user/data/raw
    mkdir -p /home/user/data/processed
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/data/raw/server_metrics_1.csv
2023-10-01T08:15:30Z,CPU_USAGE,45.2,OK
2023/10/01 08:20:00,MEMORY_USAGE,1024,WARN
2023-10-01T08:25:00Z,DISK_IO,10.5,OK
EOF

    cat << 'EOF' > /home/user/data/raw/server_metrics_2.csv
2023/10/02 09:00:00,CPU_USAGE,55.0,OK
corrupted_line_no_commas
2023-10-02T09:05:00Z,MEMORY_USAGE,2048,OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
