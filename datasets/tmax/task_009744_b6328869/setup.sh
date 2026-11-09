#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.txt
2023-10-01 14:02:15 | JP | サーバーのステータスは正常です CPU:45%
2023-10-01 14:04:10 | JP | サーバーのステータスは正常です CPU:48%
2023-10-01 14:08:30 | US | System operating normally CPU:52%
2023-10-01 14:09:59 | ES | Operación exitosa CPU:30%
2023-10-01 14:15:00 | JP | 警告: 高負荷 CPU:89%
2023-10-01 14:16:10 | ES | Operación exitosa CPU:32%
2023-10-01 14:18:22 | US | High latency detected CPU:77%
2023-10-01 14:22:00 | US | System operating normally CPU:40%
2023-10-01 14:25:30 | JP | システム復旧 CPU:20%
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
