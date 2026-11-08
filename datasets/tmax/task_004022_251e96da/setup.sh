#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023-10-01T10:00:00Z] INFO - User accessed /api/v1/data | response_ms=45 load=0.55
[2023-10-01T10:02:00Z] INFO - User accessed /api/v1/status | response_ms=10 load=0.65
[2023-10-01T10:01:00Z] INFO - User accessed /api/v1/users | response_ms=120 load=
[2023-10-01T10:02:00Z] INFO - User accessed /api/v1/status | response_ms=10 load=0.65
[2023-10-01T10:03:00Z] ERROR - Database connection failed
[2023-10-01T10:04:00Z] INFO - User accessed /api/v1/data | response_ms=50 load=0.75
[2023-10-01T10:05:00Z] INFO - User accessed /api/v1/settings | response_ms=30 load=
[2023-10-01T10:06:00Z] INFO - User accessed /api/v1/profile | response_ms=80 load=0.85
EOF

    chmod -R 777 /home/user
