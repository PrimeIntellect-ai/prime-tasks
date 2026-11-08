#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import random

def setup_environment():
    log_path = '/home/user/access_logs.jsonl'

    ips = [
        ("10.1.1.1", 1500),
        ("10.1.1.2", 1000),
        ("10.1.1.3", 800),
        ("10.1.1.4", 200),
        ("192.168.0.5", 150)
    ]

    lines = []

    # Valid lines with IPs
    for ip, count in ips:
        for _ in range(count):
            lines.append(json.dumps({"ip": ip, "endpoint": "/api/v1/data", "status": 200}) + "\n")

    # Valid JSON but missing IP (counts as invalid per rules)
    for _ in range(50):
        lines.append(json.dumps({"endpoint": "/api/v1/health", "status": 200}) + "\n")

    # Invalid JSON (bad unicode escape)
    for _ in range(45):
        lines.append('{"ip": "172.16.0.1", "msg": "User typed \\u123Z and caused an error"}\n')

    # Shuffle so they aren't clumped
    random.seed(42)
    random.shuffle(lines)

    with open(log_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)

if __name__ == "__main__":
    setup_environment()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
