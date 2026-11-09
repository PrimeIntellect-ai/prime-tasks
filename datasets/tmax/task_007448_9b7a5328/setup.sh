#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar gzip
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > log1.json
{"timestamp": "2023-10-01T10:00:00Z", "level": "INFO", "service": "web", "message": "Started processing"}
{"timestamp": "2023-10-01T10:05:00Z", "level": "ERROR", "service": "db", "message": "Connection timeout"}
{"timestamp": "2023-10-01T10:06:00Z", "level": "WARN", "service": "db", "message": "Retrying connection"}
EOF

    cat << 'EOF' > log2.json
{"timestamp": "2023-10-01T10:10:00Z", "level": "ERROR", "service": "auth", "message": "Invalid credentials provided"}
{"timestamp": "2023-10-01T10:15:00Z", "level": "INFO", "service": "auth", "message": "Login successful"}
EOF

    tar -czf logs.tar.gz log1.json log2.json
    rm log1.json log2.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
