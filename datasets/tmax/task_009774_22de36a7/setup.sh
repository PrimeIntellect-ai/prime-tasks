#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_logs.txt
[2023-10-01 10:00:01] [INFO] [192.168.1.1] System started
[2023-10-01 10:05:22] [ERROR] [10.0.0.5] ErrorCode: 404 - Not found
[2023-10-01 10:06:00] [WARN] [10.0.0.5] High memory usage
[2023-10-01 10:10:15] [FATAL] [192.168.1.100] ErrorCode: 500 - DB connection lost
[2023-10-01 10:11:00] [ERROR] [10.0.0.6] ErrorCode: 404 - Not found
[2023-10-01 10:12:00] [ERROR] [10.0.0.7] ErrorCode: 403 - Forbidden
[2023-10-01 10:15:00] [FATAL] [10.0.0.7] ErrorCode: 500 - DB connection lost
EOF

    chmod -R 777 /home/user
