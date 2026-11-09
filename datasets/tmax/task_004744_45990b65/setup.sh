#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/data/raw_events.csv
2023-10-25T14:05:00Z,alice.smith@corp.com,deposit,100
2023-10-25T14:35:12Z,bob.jones@startup.io,withdrawal,50
2023-10-25T14:45:00Z,alice.smith@corp.com,deposit,200
2023-10-25T15:10:00Z,charlie@domain.com,deposit,300
2023-10-25T15:20:00Z,bob.jones@startup.io,deposit,150
2023-10-25T15:25:00Z,bad.row@error.com,description
with newline,400
2023-10-25T15:30:00Z,david@test.com,withdrawal,50
invalid,row,format
2023-10-26T09:12:00Z,alice.smith@corp.com,deposit,500
EOF

    chmod -R 777 /home/user
