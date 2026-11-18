#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.csv
id,timestamp,raw_message
1,2023-10-01T10:00:00,Database connection failed due to timeout.
2,2023-10-01T10:05:00,User authentication successful.
3,2023-10-01T10:10:00,CRITICAL: Server overload detected, impending crash!
4,2023-10-01T10:15:00,Warning: High memory usage on server.
5,2023-10-01T10:20:00,Server crash reported by user.
6,2023-10-01T10:25:00,Disk space critical on server.
EOF

    chmod -R 777 /home/user
