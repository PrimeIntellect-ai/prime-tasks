#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import os

log_path = '/home/user/system_events.log'

events = {
    "10:00": ["System started."],
    "10:01": ["User  logged in!!", "DB connected..."],
    "10:02": ["User logged in!!"],
    "10:03": ["DB connected...", "Query executed successfully."],
    "10:04": ["Query executed successfully."],
    "10:05": ["Error 1", "Error 2", "Error 3", "Error 4", "Error 5", "Error 6", "Error 7", "Error 8"],
    "10:06": ["Fail A", "Fail B", "Fail C", "Fail D"],
    "10:07": ["System ok."]
}

with open(log_path, 'w') as f:
    for minute, msgs in events.items():
        for i, msg in enumerate(msgs):
            f.write(f"[2023-10-24 {minute}:0{i}] INFO - {msg}\n")
            if i % 2 == 0:
                f.write(f"[2023-10-24 {minute}:1{i}] INFO - {msg.upper()}\n")
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
