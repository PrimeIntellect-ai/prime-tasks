#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

log_content = b"""[2023-10-24 09:59:45] 192.168.1.1 GET /api/v1/status 200
[2023-10-24 10:00:15] 10.0.0.1 GET /api/v1/users/42/profile 200
[2023-10-24 10:00:50] 10.0.0.2 POST /api/v1/Item/100 201
[2023-10-24 10:02:10] 192.168.1.100 GET /api/v1/users/99/profile 200
[2023-10-24 10:02:45] 10.0.0.3 GET /api/V1/item/100\xff 400
[2023-10-24 10:05:05] 192.168.1.50 GET /API/v1/USERS/1/profile 200
[2023-10-24 10:09:30] 10.0.0.4 GET /api/v1/status 200
[2023-10-24 10:10:05] 192.168.1.1 GET /api/v1/status 200
"""

with open('/home/user/raw_logs.log', 'wb') as f:
    f.write(log_content)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
