#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored_logparser/vendored_logparser
    mkdir -p /opt/oracle

    # Create setup.py
    cat << 'EOF' > /app/vendored_logparser/setup.py
from setuptools import setup, find_packages
setup(
    name='vendored_logparser',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    # Create __init__.py
    touch /app/vendored_logparser/vendored_logparser/__init__.py

    # Create locking.py
    cat << 'EOF' > /app/vendored_logparser/vendored_logparser/locking.py
import os
# import fcntl

class SecureLocker:
    def __init__(self, lock_file):
        self.lock_file = lock_file
        self.fd = None

    def acquire(self):
        self.fd = open(self.lock_file, 'w')
        fcntl.flock(self.fd, fcntl.LOCK_EX)

    def release(self):
        if self.fd:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            self.fd.close()
EOF

    # Create parser.py
    cat << 'EOF' > /app/vendored_logparser/vendored_logparser/parser.py
def parse_line(line):
    parts = line.strip().split(' ', 3)
    if len(parts) < 4:
        return {"timestamp": "UNKNOWN", "payload": line.strip()}
    return {"timestamp": f"{parts[0]} {parts[1]}", "payload": parts[3]}
EOF

    # Install the vendored package in editable mode so it can be fixed in place
    cd /app/vendored_logparser
    pip3 install -e .

    # Create a dummy oracle file
    cat << 'EOF' > /opt/oracle/log_transformer_oracle
#!/usr/bin/env python3
print("Oracle placeholder")
EOF
    chmod +x /opt/oracle/log_transformer_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
