#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar
    pip3 install pytest

    mkdir -p /home/user/server_logs/app1
    mkdir -p /home/user/server_logs/app2/old_logs

    cat << 'EOF' > /home/user/server_logs/app1/service.log
{"id": 10, "level": "INFO", "msg": "Booting up system"}
{"id": 12, "level": "FATAL", "msg": "NullPointerException in thread main"}
{"id": 15, "level": "ERROR", "msg": "Failed to connect to DB"}
{"id": 18, "level": "FATAL", "msg": "Out of memory"}
{"id": 19, "level": "FAT
EOF

    cat << 'EOF' > /home/user/server_logs/app2/old_logs/archive.log
{"id": 2, "level": "FATAL", "msg": "Disk space critically low"}
{"id": 5, "level": "INFO", "msg": "User logged in"}
{"id": 8, "level": "FATAL", "msg": "Network partition detected"}
{"id": 9, "level": "W
EOF
    gzip /home/user/server_logs/app2/old_logs/archive.log

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/server_logs
    chmod -R 777 /home/user
