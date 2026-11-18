#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libjansson-dev espeak-ng
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    espeak-ng -w /app/config.wav "The rolling aggregation window size is exactly five records."

    cat << 'EOF' > /app/corpus/clean/clean.jsonl
{"timestamp": "2023-01-01T12:00:00Z", "bytes": 100, "message": "Connection established successfully"}
{"timestamp": "2023-01-01T12:01:00Z", "bytes": 200, "message": "Data transfer \u004F\u004B"}
{"timestamp": "2023-01-01T12:02:00Z", "bytes": 150, "message": "Normal user activity"}
EOF

    cat << 'EOF' > /app/corpus/evil/evil.jsonl
{"timestamp": "2023-01-01T12:03:00Z", "bytes": 5000, "message": "Beginning \u0045\u0058\u0046\u0049\u004C of sensitive data"}
{"timestamp": "2023-01-01T12:04:00Z", "bytes": 8000, "message": "Testing \u0045XF\u0049L bypass"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
