#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.csv
timestamp,app_server,db_server,web_server
2023-10-01 10:15:00,"Started process
[INFO] All good","[ERROR] Timeout
Retrying","[INFO] Serving traffic"
2023-10-01 10:45:00,"[ERROR] Failed to fetch",,
2023-10-01 12:05:00,"[ERROR] Crash
Dump saved",,"[ERROR] 500 Internal"
2023-10-01 14:30:00,"[INFO] Restarted",,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
