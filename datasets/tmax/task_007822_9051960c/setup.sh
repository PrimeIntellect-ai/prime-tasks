#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_script.py
import json

data = [
    {"timestamp": 1600000000, "log_id": "L1", "feedback_text": "Hello World", "cpu_temperature": 40.0},
    {"timestamp": 1600000050, "log_id": "L2", "feedback_text": "  Hello World  ", "cpu_temperature": 99.9},
    {"timestamp": 1600000010, "log_id": "L3", "feedback_text": "Great caf\u00e9", "cpu_temperature": None},
    {"timestamp": 1600000020, "log_id": "L4", "feedback_text": "Great cafe\u0301", "cpu_temperature": 43.0},
    {"timestamp": 1600000030, "log_id": "L5", "feedback_text": "こんにちは🌍", "cpu_temperature": None},
    {"timestamp": 1600000040, "log_id": "L6", "feedback_text": "System crash", "cpu_temperature": 49.0},
    {"timestamp": 1600000060, "log_id": "L7", "feedback_text": "Goodbye", "cpu_temperature": None}
]

with open('/home/user/app_logs.jsonl', 'w', encoding='utf-8') as f:
    for d in data:
        f.write(json.dumps(d, ensure_ascii=False) + '\n')
EOF

    python3 /home/user/setup_script.py
    rm /home/user/setup_script.py

    chmod -R 777 /home/user
