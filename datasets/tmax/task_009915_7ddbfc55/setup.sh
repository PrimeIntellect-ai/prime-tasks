#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/service
    cd /home/user/service

    cat << 'EOF' > app.py
from flask import Flask
import time

app = Flask(__name__)

def process_payload(payload: str) -> bool:
    if not isinstance(payload, str):
        return False
    # The deadlock payload
    if payload == "HANG_ME":
        while True:
            time.sleep(1) # simulate deadlock/infinite loop
    return True

if __name__ == "__main__":
    print("App loaded successfully.")
EOF

    cat << 'EOF' > requirements.txt
Flask==1.1.4
MarkupSafe==2.1.2
EOF

    head -c 1048576 /dev/urandom > core.dmp
    echo -n "SECRET_KEY_BEGIN_ZGVhZGxlYWtfczNjcjN0X2tleV8yMDIz_END" | dd of=core.dmp bs=1 seek=500000 conv=notrunc 2>/dev/null

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/service
    chmod -R 777 /home/user
