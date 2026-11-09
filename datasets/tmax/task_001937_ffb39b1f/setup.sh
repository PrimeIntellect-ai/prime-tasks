#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
2023-10-01 03:15:30,MAINTENANCE
2023-10-01 03:15:30,MAINTENANCE
2023-10-01 07:45:00,ACTIVE
2023-10-01 08:05:10,WARNING
2023-10-01 08:05:10,WARNING
2023-10-01 08:05:10,WARNING
2023-10-01 12:00:00,ACTIVE
2023-10-01 15:30:22,ERROR
2023-10-01 15:30:22,ERROR
2023-10-01 19:59:59,MAINTENANCE
EOF

    chmod -R 777 /home/user
