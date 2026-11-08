#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/monitor.py
def process_heartbeat(payload):
    if payload.startswith(b"HEARTBEAT"):
        parts = payload.split(b"|")
        if len(parts) == 4:
            if parts[2] == b"0x00":
                if parts[3] == b"PANIC":
                    raise RuntimeError("Panic on unwrap()")
    return True
EOF

    python3 -m py_compile /home/user/monitor.py
    mv /home/user/__pycache__/monitor.*.pyc /home/user/monitor.pyc
    rm -rf /home/user/__pycache__
    rm /home/user/monitor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
