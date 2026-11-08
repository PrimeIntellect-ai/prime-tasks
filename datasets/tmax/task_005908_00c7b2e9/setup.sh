#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_01.log
[INFO] System boot sequence initiated.
[TRACE] Loading storage drivers...
[TRACE] Mounting volumes...
[INFO] Volumes mounted successfully.
[ERROR] Disk quota exceeded ERROR_CODE:999
[TRACE] Attempting auto-cleanup...
[INFO] Cleanup yielded 500MB.
[ERROR] Database sync failed ERROR_CODE:999
[INFO] System running.
EOF

    tar -czf /home/user/system_logs.tar.gz -C /home/user server_01.log
    rm /home/user/server_01.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
