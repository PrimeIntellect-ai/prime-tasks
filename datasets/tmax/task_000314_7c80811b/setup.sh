#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/quotalogger-2.1/systemd
    mkdir -p /app/quotalogger-2.1/quotalogger
    mkdir -p /app/data
    mkdir -p /home/user/.config/systemd/user

    # Create mock-db.service
    cat << 'EOF' > /home/user/.config/systemd/user/mock-db.service
[Unit]
Description=Mock DB Service

[Service]
ExecStart=/bin/sleep infinity
Restart=always

[Install]
WantedBy=default.target
EOF

    # Create quotalogger.service template
    cat << 'EOF' > /app/quotalogger-2.1/systemd/quotalogger.service
[Unit]
Description=Quota Logger Service

[Service]
ExecStart=/usr/local/bin/quotalogger-cli /app/data/test_logs.txt
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    # Create quotalogger/parser.py (inefficient version)
    cat << 'EOF' > /app/quotalogger-2.1/quotalogger/parser.py
def calculate_quotas(log_path):
    users = []
    total = 0
    with open(log_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 3:
                user, file_id, size = parts
                if user not in users:
                    users.append(user)
                total += int(size)
    print(f"TOTAL_USAGE: {total}")
    return total
EOF

    # Create quotalogger/__init__.py
    touch /app/quotalogger-2.1/quotalogger/__init__.py

    # Create setup.py
    cat << 'EOF' > /app/quotalogger-2.1/setup.py
from setuptools import setup, find_packages

setup(
    name="quotalogger",
    version="2.1",
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'quotalogger-cli=quotalogger.cli:main',
        ],
    },
)
EOF

    # Create quotalogger/cli.py
    cat << 'EOF' > /app/quotalogger-2.1/quotalogger/cli.py
import sys
from .parser import calculate_quotas

def main():
    if len(sys.argv) > 1:
        calculate_quotas(sys.argv[1])
    else:
        print("Usage: quotalogger-cli <log_file>")
EOF

    # Generate test logs
    cat << 'EOF' > /tmp/gen_logs.py
import random
with open('/app/data/test_logs.txt', 'w') as f:
    for i in range(50000):
        f.write(f"user{random.randint(1, 1000)},file{i},{random.randint(10, 1000)}\n")
EOF
    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
