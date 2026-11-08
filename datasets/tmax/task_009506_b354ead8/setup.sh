#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logs.txt
2023-10-01 10:00:00 | ERROR | Db connection timed out unexpectedly!
2023-10-01 10:05:00 | WARNING | Disk /dev/sda1 is at 99% capacity.
2023-10-01 10:10:00 | CRITICAL | Out of memory error allocating 4096 bytes.
2023-10-01 10:15:00 | INFO | User admin logged in successfully.
2023-10-01 10:20:00 | ERROR | Network db timeout during sync.
EOF

    cat << 'EOF' > /home/user/categories.csv
category_name,reference_text
Database Issue,database db connection timeout
Disk Issue,disk capacity full space low
Memory Issue,memory out of ram allocation
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
