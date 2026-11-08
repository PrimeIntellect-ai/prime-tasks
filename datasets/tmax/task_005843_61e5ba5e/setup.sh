#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo build-essential
    pip3 install pytest

    mkdir -p /home/user/organized_logs
    cat << 'EOF' > /home/user/raw_logs.jsonl
{"timestamp": "2023-11-01T10:00:01Z", "module": "api", "level": "INFO", "message": "Request started"}
{"timestamp": "2023-11-01T10:00:02Z", "module": "db", "level": "DEBUG", "message": "Connecting to postgres"}
{"timestamp": "2023-11-01T10:00:03Z", "module": "api", "level": "WARN", "message": "Rate limit approaching"}
{"timestamp": "2023-11-01T10:00:04Z", "module": "auth", "level": "ERROR", "message": "Invalid token format"}
{"timestamp": "2023-11-01T10:00:05Z", "module": "db", "level": "INFO", "message": "Query executed in 5ms"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
