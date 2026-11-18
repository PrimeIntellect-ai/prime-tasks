#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import csv
import os

csv_path = "/home/user/raw_chat_logs.csv"

data = [
    ["2023-10-01T10:00:00Z", "U001", "Hello, I need help with my account. My email is john.doe@example.com."],
    ["2023-10-01T10:01:00Z", "U002", "Hi\nI can't log in.\nPlease help!"],
    ["2023-10-01T10:05:00Z", "U001", "Hello, I need help with my account! My email is [EMAIL]."],
    ["2023-10-01T10:06:00Z", "U003", "Reset password for admin@corp.com"],
    ["2023-10-01T10:10:00Z", "U002", "Nevermind, I figured it out.\nThanks!"],
    ["2023-10-01T10:15:00Z", "U001", "Please cancel my subscription."],
    ["2023-10-01T10:16:00Z", "U001", "Please cancel my subscription immediately."],
]

with open(csv_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "user_id", "message"])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
