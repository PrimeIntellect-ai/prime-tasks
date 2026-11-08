#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data_loader
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/data_loader/loader.py
def load_data():
    # Base latency of 100,000 ms with microsecond variations
    return [100000.0 + (i % 10)*1e-5 for i in range(10000)]
EOF

    cat << 'EOF' > /home/user/metrics.py
def calculate_variance(data):
    n = len(data)
    if n == 0: return 0.0
    sum_x = sum(data)
    sum_x2 = sum(x**2 for x in data)
    mean = sum_x / n
    # Catastrophic cancellation occurs here
    return (sum_x2 / n) - (mean ** 2)
EOF

    cat << 'EOF' > /home/user/bin/monitor.py
import math
import sys
import os

# Circular import simulation or missing path
from data_loader.loader import load_data
from metrics import calculate_variance

def main():
    data = load_data()
    var = calculate_variance(data)
    stddev = math.sqrt(var)
    print(f"Standard Deviation: {stddev}")
    with open('/home/user/result.log', 'w') as f:
        f.write(str(stddev))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
