#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/config_audit.log
2023-10-01T10:00:00Z alice web-01 worker_threads 16 32
2023-10-01T10:05:00Z bob db-02 max_memory 1024 2048
2023-10-01T10:10:00Z alice web-02 worker_threads 16 36
2023-10-01T10:15:00Z charlie web-01 timeout 30 60
2023-10-01T10:20:00Z admin web-03 worker_threads 32 40
2023-10-01T10:25:00Z alice web-01 worker_threads 32 44
2023-10-01T10:30:00Z bob web-02 worker_threads 36 37
2023-10-01T10:35:00Z admin web-03 worker_threads 40 44
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
