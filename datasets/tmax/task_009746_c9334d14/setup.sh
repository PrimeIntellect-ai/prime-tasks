#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    mkdir -p /home/user/backup_source/db1
    mkdir -p /home/user/backup_source/db2/logs

    cat << 'EOF' > /home/user/backup_source/db1/data.csv
id,data
500,init
1001,update
1050,final
EOF

    cat << 'EOF' > /home/user/backup_source/db1/old_data.csv
id,data
10,init
999,final
EOF

    cat << 'EOF' > /home/user/backup_source/db2/logs/001.wal
TXN_ID: 800
DATA: start
EOF

    cat << 'EOF' > /home/user/backup_source/db2/logs/002.wal
TXN_ID: 2048
DATA: checkpoint
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
