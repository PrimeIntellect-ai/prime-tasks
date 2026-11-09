#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/raw
    mkdir -p /home/user/backups/processed

    cat << 'EOF' > /home/user/backups/raw/export_A_final.txt
SERVER,DATE,STATUS,METRIC
Web01,20231024,ACTIVE,4920
Web01,20231024,IDLE,112
EOF

    cat << 'EOF' > /home/user/backups/raw/db_dump_random.txt
SERVER,DATE,STATUS,METRIC
DB_MAIN,20231025,SYNC,9999
DB_MAIN,20231025,BACKUP,8888
EOF

    cat << 'EOF' > /home/user/backups/raw/cache-log-11.txt
SERVER,DATE,STATUS,METRIC
REDIS_01,20231026,OK,555
REDIS_01,20231026,WARN,444
EOF

    chown -R user:user /home/user/backups
    chmod -R 777 /home/user
