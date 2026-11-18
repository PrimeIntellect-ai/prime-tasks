#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/vendored/ts_distance/ts_distance
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    cat << 'EOF' > /app/vendored/ts_distance/setup.py
import setuptool # Deliberate error
from setuptools import setup, Extension

setup(
    name='ts_distance',
    version='1.0.0',
    packages=['ts_distance'],
)
EOF

    cat << 'EOF' > /app/vendored/ts_distance/ts_distance/__init__.py
def compute_dtw(seq1, seq2):
    # Mock DTW for the sake of the task verifier
    return sum(abs(a - b) for a, b in zip(seq1, seq2)) + abs(len(seq1) - len(seq2)) * 10.0
EOF

    # Create data files using python
    python3 -c '
import os

with open("/app/data/clean/clean1.json", "wb") as f:
    f.write(b"{\"sensor_readings\": [0.0, 1.0, null, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]}")

with open("/app/data/clean/clean2.json", "wb") as f:
    f.write("{\"sensor_readings\": [0.0, 2.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]}".encode("utf-16-le"))

with open("/app/data/evil/evil1_hash.json", "wb") as f:
    f.write(b"{\"sensor_readings\": []}")

with open("/app/data/evil/evil2_dist.json", "wb") as f:
    f.write(b"{\"sensor_readings\": [100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0]}")

with open("/app/data/evil/evil3_malformed.json", "wb") as f:
    f.write(b"\xff\xfe\xff\xffmalformed")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
