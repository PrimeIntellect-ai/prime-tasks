#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip acl systemd tzdata build-essential
    pip3 install --default-timeout=100 pytest Cython setuptools

    useradd -m -s /bin/bash user || true

    mkdir -p /app/fast-metric-exporter/bin

    cat << 'EOF' > /app/fast-metric-exporter/setup.py
from setuptools import setup
from Cython.Build import cythonize

setup(
    name="fast-metric-exporter",
    version="1.0.0",
    ext_modules=[],
    scripts=["bin/fast-metric-exporter"]
)
EOF

    cat << 'EOF' > /app/fast-metric-exporter/parser.pyx
def parse_logs(logfile):
    return {"timezone_parsed": True, "lines": 500000}
EOF

    cat << 'EOF' > /app/fast-metric-exporter/bin/fast-metric-exporter
#!/usr/bin/env python3
import sys
import json
import os
import time

# Fallback or Cython
try:
    import parser
    data = parser.parse_logs("/home/user/app_logs/input.log")
except ImportError:
    time.sleep(15)
    data = {"timezone_parsed": True, "lines": 500000}

with open("/home/user/metrics.json", "w") as f:
    json.dump(data, f)
EOF
    chmod +x /app/fast-metric-exporter/bin/fast-metric-exporter

    mkdir -p /home/user/app_logs
    touch /home/user/app_logs/input.log

    chown -R user:user /app/fast-metric-exporter
    chown -R user:user /home/user/app_logs

    chmod -R 777 /home/user
