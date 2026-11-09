#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/logs
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/logs/log_1.jsonl
{"timestamp": 1700000000, "cpu_usage": 50.0, "message": "status ok"}
{"timestamp": 1700000010, "cpu_usage": 60.0, "message": "status ok"}
{"timestamp": 1700000000, "cpu_usage": 50.0, "message": "status ok"}
{"timestamp": 1700000020, "cpu_usage": 70.0, "message": "bad unicode \uZZZZ"}
EOF

    cat << 'EOF' > /home/user/data/logs/log_2.jsonl
{"timestamp": 1700000030, "cpu_usage": 80.0, "message": "status ok"}
{"timestamp": 1700000020, "cpu_usage": 70.0, "message": "bad unicode \uZZZZ"}
{"timestamp": 1700000040, "cpu_usage": 90.0, "message": "status ok"}
EOF

    chmod -R 777 /home/user
