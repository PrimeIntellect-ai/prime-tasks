#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/remote_archive

    cat << 'EOF' > /home/user/logs/serverA.log
[2023-11-01T08:00:00Z] MAX_CONNECTIONS=100
[2023-11-01T08:15:30Z] TIMEOUT=30
[2023-11-01T09:00:00Z] WORKER_THREADS=4
[2023-11-01T10:30:00Z] CACHE_SIZE=1024
EOF

    cat << 'EOF' > /home/user/logs/serverB.log
[2023-11-01T08:00:00Z] MAX_CONNECTIONS=200
[2023-11-01T08:20:00Z] RETRY_LIMIT=5
[2023-11-01T09:00:00Z] WORKER_THREADS=8
[2023-11-01T10:30:00Z] LOG_LEVEL=DEBUG
[2023-11-01T11:00:00Z] CACHE_SIZE=2048
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
