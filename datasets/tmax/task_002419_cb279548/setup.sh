#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev libjansson-dev libcjson-dev pkg-config
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/thresholds.json
{
  "/var/log": 500,
  "/home/users": 2000,
  "/data/db": 10000,
  "/": 50000
}
EOF

    cat << 'EOF' > /home/user/logs/log.01.csv
2023-10-25 14:00:00,/var/log,450
2023-10-25 14:00:00,/home/users,1800
2023-10-25 14:00:00,/data/db,9500
2023-10-25 14:05:00,/var/log,505
2023-10-25 14:05:00,/home/users,2100
2023-10-25 14:05:00,/data/db,9800
EOF

    cat << 'EOF' > /home/user/logs/log.02.csv
2023-10-25 14:10:00,/var/log,510
2023-10-25 14:10:00,/home/users,1900
2023-10-25 14:10:00,/data/db,10050
2023-10-25 14:10:00,/backup,80000
EOF

    chown -R user:user /home/user/logs /home/user/thresholds.json
    chmod -R 777 /home/user
