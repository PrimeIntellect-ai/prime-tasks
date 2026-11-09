#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_stats.py
import math

def calculate_metrics(data):
    sum_x = 0.0
    sum_x2 = 0.0
    n = len(data)
    for x in data:
        sum_x += x
        sum_x2 += x**2

    mean = sum_x / n
    variance = (sum_x2 / n) - (mean**2)

    std_dev = math.sqrt(variance)
    return mean, std_dev
EOF

    python3 -m py_compile /home/user/legacy_stats.py
    mv /home/user/__pycache__/legacy_stats.*.pyc /home/user/legacy_stats.pyc
    rm -rf /home/user/__pycache__
    rm /home/user/legacy_stats.py

    chmod -R 777 /home/user
