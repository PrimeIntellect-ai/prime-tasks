#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

data = [
    (1630000000, b"srv-alpha", b"db_timeout", b"30s"),
    (1630000005, b"srv-beta", b"db_timeout", b"45s"),
    (1630000010, b"srv-alpha", b"welcome_msg", b"Hello \x93World\x94"),
    (1630000015, b"srv-gamma", b"welcome_msg", b"Maintenance \x85"),
    (1630000002, b"srv-beta", b"timezone", b"Europe/Paris"),
    (1630000020, b"srv-alpha", b"db_timeout", b"60s"),
    (1630000001, b"srv-delta", b"system_path", b"C:\\Windows\\System32"),
]

os.makedirs("/home/user", exist_ok=True)
with open('/home/user/config_events.tsv', 'wb') as f:
    for ts, srv, k, v in data:
        line = str(ts).encode('utf-8') + b'\t' + srv + b'\t' + k + b'\t' + v + b'\n'
        f.write(line)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
