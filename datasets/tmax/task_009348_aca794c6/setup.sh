#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_server_logs.txt
[2023-10-25 14:32:10.111] INFO: System started - ID:sys_000
[2023-10-25 14:32:45.123] ERROR: Connection timeout - ID:usr_123
[2023-10-25 14:32:55.999] ERROR: Connection timeout - ID:usr_123
[2023-10-25 14:33:05.000] ERROR: Disk full - ID:sys_001
[2023-10-25 14:33:10.555] ERROR: Connection timeout - ID:usr_123
[2023-10-25 14:33:59.001] INFO: Retry successful - ID:usr_123
[2023-10-25 14:34:01.000] ERROR: Disk full - ID:sys_001
EOF

    chmod -R 777 /home/user
