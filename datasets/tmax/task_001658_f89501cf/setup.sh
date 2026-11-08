#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip logrotate netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/qemu_mock.py
#!/usr/bin/env python3
import socket
import sys
import time
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('-vnc', type=str, required=True)
args = parser.parse_args()

if args.vnc == ':2':
    port = 5902
else:
    sys.exit(1)

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', port))
s.listen(1)
while True:
    time.sleep(10)
EOF
    chmod +x /home/user/qemu_mock.py

    chmod -R 777 /home/user
