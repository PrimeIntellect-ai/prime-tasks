#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/vendor/log_extractor-1.0/log_extractor
    mkdir -p /app/oracle

    cat << 'EOF' > /app/vendor/log_extractor-1.0/setup.py
from setuptools import setup, find_packages

setup(
    name='log_extractor',
    version='1.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/vendor/log_extractor-1.0/log_extractor/__init__.py
from .core import parse_log
EOF

    cat << 'EOF' > /app/vendor/log_extractor-1.0/log_extractor/core.py
def parse_log(log_bytes):
    return log_bytes.decode('ascii') # BUG: Should be utf-8
EOF

    cat << 'EOF' > /app/oracle/analyzer_oracle.py
#!/usr/bin/env python3
import sys, json, base64

def check_anomaly(msg):
    markers = ["🚨", "CRÍTICO", "严重", "KRITISCH"]
    return any(m in msg for m in markers)

def main():
    input_data = sys.stdin.read().strip()
    if not input_data:
        return
    data = json.loads(input_data)
    raw_bytes = base64.b64decode(data["raw_b64"])
    msg = raw_bytes.decode('utf-8')
    out = {
        "uid": data["uid"],
        "message_length": len(msg),
        "is_anomaly": check_anomaly(msg)
    }
    print(json.dumps(out))

if __name__ == "__main__":
    main()
EOF

    chmod +x /app/oracle/analyzer_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
