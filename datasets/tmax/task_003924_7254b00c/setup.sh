#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest setuptools

mkdir -p /app/vendored/loglocker-0.1.0/loglocker

cat << 'EOF' > /app/vendored/loglocker-0.1.0/setup.py
from setuptools import setup, find_packages
setup(
    name="loglocker",
    version="0.1.0",
    packages=find_packages(),
)
EOF

cat << 'EOF' > /app/vendored/loglocker-0.1.0/loglocker/__init__.py
from .locker import Lock
EOF

cat << 'EOF' > /app/vendored/loglocker-0.1.0/loglocker/locker.py
import os
import fcntl

class Lock:
    def __init__(self, name):
        self.lockfile = f"/tmp/{name}.lock"
        self.fd = None

    def __enter__(self):
        # Deliberately broken file mode: O_RDONLY instead of O_RDWR | O_CREAT
        self.fd = os.open(self.lockfile, os.O_RDONLY, 0o666)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)
EOF

mkdir -p /opt/oracle
cat << 'EOF' > /opt/oracle/incremental_pack
#!/usr/bin/env python3
import sys
import zlib
import re

def process():
    data = sys.stdin.read()
    lines = data.split('\n')
    out_lines = []

    ip_pattern = re.compile(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}')

    # If the input doesn't end with a newline, split('\n') leaves an empty string at the end.
    # We must match standard iteration behavior.
    for i, line in enumerate(lines):
        if i == len(lines) - 1 and not line:
            continue # Skip trailing empty from split

        if "DEBUG" in line:
            continue

        # Replace IP
        line = ip_pattern.sub(r'\g<1>XXX', line)
        out_lines.append(line)

    if out_lines:
        out_text = '\n'.join(out_lines) + '\n'
        # Handle case where original input had no trailing newline
        if data and not data.endswith('\n'):
            out_text = '\n'.join(out_lines)
    else:
        out_text = ""

    compressed = zlib.compress(out_text.encode('utf-8'))
    sys.stdout.buffer.write(compressed)

if __name__ == "__main__":
    process()
EOF
chmod +x /opt/oracle/incremental_pack

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
