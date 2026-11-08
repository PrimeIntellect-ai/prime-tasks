#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas pyarrow fastparquet

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw /home/user/data/processed

    cat << 'EOF' > /home/user/data/raw/log_01.txt
[2023-10-25 14:30:00] REQ:r001 USER:u1 TIME:100ms
[2023-10-25 14:31:00] REQ:r002 USER:u1 TIME:150ms
[2023-10-25 14:32:00] REQ:r003 USER:u2 TIME:50ms
[2023-10-25 14:33:00] REQ:r004 USER:u1 TIME:200ms
[2023-10-25 14:34:00] REQ:r005 USER:u1 TIME:100ms
EOF

    chmod -R 777 /home/user
