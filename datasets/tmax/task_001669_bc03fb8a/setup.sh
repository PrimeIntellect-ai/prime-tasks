#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    # Create the raw_configs.jsonl file using the provided setup script
    cat << 'EOF' > /tmp/setup.py
import os
import json

data = [
    # Server A - normal
    {"timestamp": 100, "server_id": "srv-A", "temp_celsius": 40.0, "cpu_load": 10.0, "metadata": "ok"},
    {"timestamp": 110, "server_id": "srv-A", "temp_celsius": None, "cpu_load": None, "metadata": "bad \\uZZZZ"},
    {"timestamp": 120, "server_id": "srv-A", "temp_celsius": 50.0, "cpu_load": 20.0, "metadata": "ok"},
    # Server A duplicate
    {"timestamp": 120, "server_id": "srv-A", "temp_celsius": 99.0, "cpu_load": 99.0, "metadata": "dup"},

    # Server B - leading and trailing nulls
    {"timestamp": 100, "server_id": "srv-B", "temp_celsius": None, "cpu_load": None, "metadata": "\\uG123"},
    {"timestamp": 110, "server_id": "srv-B", "temp_celsius": 60.0, "cpu_load": 30.0, "metadata": "ok"},
    {"timestamp": 120, "server_id": "srv-B", "temp_celsius": 70.0, "cpu_load": 40.0, "metadata": "ok"},
    {"timestamp": 130, "server_id": "srv-B", "temp_celsius": None, "cpu_load": None, "metadata": "ok"}
]

with open("/home/user/raw_configs.jsonl", "w") as f:
    for item in data:
        # Write exact string to ensure bad unicode is preserved exactly as written
        line = json.dumps(item).replace("\\\\u", "\\u")
        f.write(line + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
