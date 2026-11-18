#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app_logs.txt
[INFO] Server started on port 8080.
[DEBUG] User authentication attempt.
[WARN] Deprecated auth token found: <SECRET:150416161a747776>
[INFO] Authentication successful.
[DEBUG] Payload metadata: <SECRET:001122334455>
[WARN] Deprecated auth token found: <SECRET:3f2e3c3c301a1d18>
[INFO] Connection closed.
EOF

    chmod -R 777 /home/user
