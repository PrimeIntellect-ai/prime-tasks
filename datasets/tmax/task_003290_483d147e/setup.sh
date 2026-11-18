#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/vendored/py-rolling-stats-0.1.0/py_rolling_stats

    # Create setup.py
    cat << 'EOF' > /app/vendored/py-rolling-stats-0.1.0/setup.py
from setuptools import setup, find_packages

setup(
    name='py-rolling-stats',
    version='0.1.0',
    packages=find_packages(),
)
EOF

    # Create __init__.py
    cat << 'EOF' > /app/vendored/py-rolling-stats-0.1.0/py_rolling_stats/__init__.py
from .calculator import RollingCalculator
EOF

    # Create calculator.py with intentional typo
    cat << 'EOF' > /app/vendored/py-rolling-stats-0.1.0/py_rolling_stats/calculator.py
import os
from collections import deque

class RollingCalculator:
    def __init__(self):
        self.window_size = int(os.environ.get('MAX_WINDW_SIZE', 3))
        self.values = deque(maxlen=self.window_size)

    def add(self, value):
        self.values.append(value)

    def average(self):
        if not self.values:
            return 0.0
        return sum(self.values) / len(self.values)
EOF

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Create some dummy JSONL files
    cat << 'EOF' > /home/user/corpora/evil/test_evil.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "server_id": "srv-01", "diff_size": 60, "content": "host=192.168.1.10\npassword=superSecret"}
EOF

    cat << 'EOF' > /home/user/corpora/clean/test_clean.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "server_id": "srv-02", "diff_size": 10, "content": "host=localhost\nuser=admin"}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
