#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import csv

data = [
    ["timestamp", "user_id", "region", "message"],
    ["2023-10-24 14:15:00", "101", "EU", "Hello World"],
    ["2023-10-24 14:30:00", "102", "ASIA", "こんにちは"],
    ["2023-10-24 14:45:00", "103", "EU", "Line 1\nLine 2"],
    ["2023-10-24 15:05:00", "104", "US", "Café"],
    ["2023-10-24 15:10:00", "105", "ASIA", ""],
    ["2023-10-24 15:20:00", "106", "EU", "Test\nNewline\nHere"],
    ["2023-10-24 16:00:00", "107", "US", "Valid"]
]

with open("/home/user/raw_chat_logs.csv", "w", encoding="utf-16le", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
