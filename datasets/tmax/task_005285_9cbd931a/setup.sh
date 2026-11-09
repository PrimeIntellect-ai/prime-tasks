#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest setuptools

    # Create vendored package
    mkdir -p /app/vendored/py-log-parser-1.0.0/pylogparser

    cat << 'EOF' > /app/vendored/py-log-parser-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name="py-log-parser",
    version="1.0.0",
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/vendored/py-log-parser-1.0.0/pylogparser/__init__.py
from .core import parse_line
EOF

    cat << 'EOF' > /app/vendored/py-log-parser-1.0.0/pylogparser/core.py
import re
from datetime import timezome

def parse_line(line):
    pattern = r'^(?P<ip>[\d\.]+) \S+ \S+ \[(?P<timestamp>.*?)\] "(?P<method>\S+) (?P<endpoint>\S+) \S+" \d+ \d+'
    match = re.match(pattern, line)
    if match:
        return match.groupdict()
    return {}
EOF

    # Create raw logs
    mkdir -p /home/user/raw_logs
    cat << 'EOF' > /home/user/raw_logs/app.log
10.0.0.5 - - [10/Oct/2000:13:55:36 -0700] "GET /api/data?user=123 HTTP/1.0" 200 2326
192.168.1.100 - - [10/Oct/2000:13:55:37 -0700] "POST /api/login HTTP/1.0" 200 1000
10.0.0.5 - - [10/Oct/2000:13:55:38 -0700] "GET /api/status HTTP/1.0" 200 2326
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
