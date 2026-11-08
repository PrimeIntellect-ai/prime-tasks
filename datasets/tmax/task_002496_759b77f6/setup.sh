#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/input_stream.txt
10.0
25.0
16.0
-4.0
9.0
36.0
-1.0
49.0
64.0
81.0
EOF

    cat << 'EOF' > /home/user/app/math_logic.py
def calculate_equilibrium(value):
    # Newton's method for square root, but buggy for negative numbers (oscillates/hangs)
    x = 1.0
    while True:
        next_x = 0.5 * (x + value / x)
        if abs(x - next_x) < 1e-5:
            break
        x = next_x
    return x
EOF

    cat << 'EOF' > /home/user/app/worker.py
import time
from math_logic import calculate_equilibrium

seen_records = []

def process_data(data_stream):
    results = []
    for line in data_stream:
        val = float(line.strip())

        # Memory leak here
        seen_records.append(val)

        # Will hang on negative values
        eq = calculate_equilibrium(val)
        results.append(eq)

    return results
EOF

    cat << 'EOF' > /home/user/app/run.py
import os
from worker import process_data

if __name__ == "__main__":
    with open("/home/user/app/input_stream.txt", "r") as f:
        lines = f.readlines()

    results = process_data(lines)

    with open("/home/user/app/success.txt", "w") as f:
        for r in results:
            f.write(f"{r:.4f}\n")
EOF

    chmod -R 777 /home/user
