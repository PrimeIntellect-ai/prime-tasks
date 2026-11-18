#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/access.log
{"ts": "2023-10-01T10:01:05Z", "ip": "10.0.0.5", "status": 401}
{"ts": "2023-10-01T10:02:15Z", "ip": "10.0.0.5", "status": 401}
{"ts": "2023-10-01T10:04:55Z", "ip": "10.0.0.5", "status": 401}
{"ts": "2023-10-01T10:06:05Z", "ip": "10.0.0.5", "status": 401}
{"ts": "2023-10-01T10:01:10Z", "ip": "10.0.0.9", "status": 200}
{"ts": "2023-10-01T10:01:12Z", "ip": "192.168.1.1", "status": 200}
{"ts": "2023-10-01T10:09:59Z", "ip": "10.0.0.9", "status": 500}
{"ts": "2023-10-01T10:10:00Z", "ip": "10.0.0.9", "status": 500}
EOF

    cat << 'EOF' > /home/user/threat_ips.csv
10.0.0.5,95
10.0.0.9,80
EOF

    chmod -R 777 /home/user
