#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/service_mem.log
[2023-10-01T10:00:00] 1042 Cache 500
[2023-10-01T10:00:00] 1088 Worker 200
[2023-10-01T10:00:00] 1095 Router 100
[2023-10-01T10:01:00] 1042 Cache 520
[2023-10-01T10:01:00] 1088 Worker 250
[2023-10-01T10:01:00] NULL pointer exception at 0x00000000
[2023-10-01T10:02:00] 1042 Cache 490
[2023-10-01T10:02:00] 1088 Worker 300
[2023-10-01T10:02:00] 1095 Router 100
[2023-10-01T10:03:00] 1042 Cache 510
[2023-10-01T10:03:00] 1088 Worker 350
[2023-10-01T10:03:00] 1095 Router 100
[2023-10-01T10:03:30] Kernel panic - not syncing: Fatal exception
[2023-10-01T10:04:00] 1088 Worker 400
[2023-10-01T10:04:00] GarbageData ^&*(%$# 123
[2023-10-01T10:05:00] 1088 Worker 450
[2023-10-01T10:05:00] 1042 Cache 505
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
