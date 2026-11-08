#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.log
2023-10-15T14:05:01Z | 10.0.0.1 | INFO | 150 | /api/login
2023-10-15T14:15:00Z | 10.0.0.2 | WARN | 200 | /api/login
2023-10-15T14:20:00Z | 10.0.0.3 | DEBUG | 500 | /api/login
2023-10-15T14:30:00Z | 10.0.0.4 | ERROR | 0 | /api/login
2023-10-15T14:35:00Z | 10.0.0.4 | ERROR | -50 | /api/login
2023-10-15T14:45:00Z | 10.0.0.5 | INFO | 100 | /health
2023-10-15T15:02:00Z | 10.0.0.6 | INFO | 300 | /api/data
2023-10-15T15:10:00Z | 10.0.0.7 | ERROR | 400 | /api/data
2023-10-15T15:20:00Z | 10.0.0.8 | INFO | 350 | /api/login
2023-10-15T15:25:00Z | 10.0.0.9 | WARN | 120 | /api/data/v2
2023-10-16T08:05:00Z | 10.0.0.10 | INFO | 45 | /api/config
2023-10-16T08:06:00Z | 10.0.0.11 | INFO | 50 | /api/config
2023-10-16T08:07:00Z | 10.0.0.12 | FATAL | 5000 | /api/config
EOF

    chmod -R 777 /home/user
