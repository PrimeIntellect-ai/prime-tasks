#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/input.csv
2023-10-01 10:00:00,Hello World! This is a test.
2023-10-01 10:05:00,Café is open!!! Welcome.
2023-10-01 10:10:00,123 numbers 456
2023-10-01 10:15:00,No-alphanumerics... here??
2023-10-01 10:20:00,short string
EOF

    chmod -R 777 /home/user
