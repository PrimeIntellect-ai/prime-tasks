#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_metrics.csv
timestamp,worker_threads
2023-10-01T10:00:00,10
2023-10-01T10:01:00,11
2023-10-01T10:02:00,10
2023-10-01T10:03:00,11
2023-10-01T10:04:00,10
2023-10-01T10:05:00,50
EOF

    chown user:user /home/user/config_metrics.csv
    chmod -R 777 /home/user
