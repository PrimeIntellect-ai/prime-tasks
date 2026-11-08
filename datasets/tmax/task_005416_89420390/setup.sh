#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create vendored package directory
    mkdir -p /app/vendored/pylogcalc-0.1.0/pylogcalc

    # Create setup.py
    cat << 'EOF' > /app/vendored/pylogcalc-0.1.0/setup.py
from setuptools import setup, find_packages
setup(name='pylogcalc', version='0.1.0', packages=find_packages())
EOF

    # Create __init__.py
    touch /app/vendored/pylogcalc-0.1.0/pylogcalc/__init__.py

    # Create parser.py with the bug
    cat << 'EOF' > /app/vendored/pylogcalc-0.1.0/pylogcalc/parser.py
def calculate_risk(log_dict):
    msg = log_dict['message']
    # BUG: forces ascii
    msg_bytes = msg.encode('ascii') 
    score = (log_dict['x']**2 + log_dict['y']**2)**0.5 + len(msg_bytes)*0.1
    return score
EOF

    # Generate logs.jsonl
    cat << 'EOF' > /tmp/generate_logs.py
import json
logs = [
    {"id": 1, "lang": "en", "message": "Login failed", "x": 1.0, "y": 2.0},
    {"id": 2, "lang": "ja", "message": "ログイン失敗", "x": 10.0, "y": 10.0},
    {"id": 3, "lang": "ar", "message": "فشل الدخول", "x": 5.0, "y": 12.0},
    {"id": 4, "lang": "en", "message": "Timeout", "x": 0.0, "y": 0.0},
    {"id": 5, "lang": "en", "message": "Error", "x": 1.0, "y": 1.0},
    {"id": 6, "lang": "en", "message": "Crash", "x": 2.0, "y": 2.0},
    {"id": 7, "lang": "en", "message": "Warning", "x": 3.0, "y": 3.0},
    {"id": 8, "lang": "en", "message": "Info", "x": 4.0, "y": 4.0},
    {"id": 9, "lang": "ja", "message": "エラー", "x": 20.0, "y": 21.0},
    {"id": 10, "lang": "ja", "message": "警告", "x": 0.0, "y": 1.0},
    {"id": 11, "lang": "ja", "message": "情報", "x": 0.0, "y": 2.0},
    {"id": 12, "lang": "ja", "message": "システム", "x": 0.0, "y": 3.0},
]
with open("/home/user/logs.jsonl", "w", encoding="utf-8") as f:
    for log in logs:
        f.write(json.dumps(log, ensure_ascii=False) + "\n")
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
