#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_logs.txt
2023-10-12 10:00:00 [INFO] - user:0000 - System startup.
2023-10-12 10:05:01 [ERROR] - user:1001 - DB connection lost. code:E-100
2023-10-12 10:06:22 [WARNING] - user:1002 - High memory usage. code:W-042
2023-10-12 10:07:05 [ERROR] - user:1003 - Retry failed. code:E-100
2023-10-12 10:08:10 [ERROR] - user:1004 - Timeout. code:E-100
2023-10-12 10:10:00 [INFO] - user:0000 - Health check passed.
2023-10-12 10:15:30 [WARNING] - user:1005 - High memory usage. code:W-042
2023-10-12 10:16:00 [WARNING] - user:1006 - Disk almost full. code:W-042
2023-10-12 10:20:00 [ERROR] - user:1007 - Unknown exception. code:E-999
EOF

    chmod -R 777 /home/user
