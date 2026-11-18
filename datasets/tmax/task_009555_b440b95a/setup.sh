#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/legacy_app

    cat << 'EOF' > /home/user/legacy_app/data.txt
0.0, 1.0, 0.1
10.0, 20.0, 0.2
0.5, 3.5, 0.15
EOF

    cat << 'EOF' > /home/user/legacy_app/app.py
import sys

# Increase recursion depth just in case
sys.setrecursionlimit(5000)

def find_equilibrium(current, target, rate):
    # Bug: Exact floating point comparison
    if current == target:
        return current

    # Failsafe to prevent complete memory lockup during tests, 
    # but still throws a deliberate exception to mimic the error.
    if current > target * 2:
        raise RecursionError("maximum recursion depth exceeded")

    return find_equilibrium(current + rate, target, rate)

def process_data(input_file, output_file):
    results = []
    with open(input_file, 'r') as f:
        for line in f:
            c, t, r = map(float, line.strip().split(','))
            res = find_equilibrium(c, t, r)
            results.append(res)

    with open(output_file, 'w') as f:
        for res in results:
            f.write(f"{res:.1f}\n")

if __name__ == "__main__":
    process_data("data.txt", "output.txt")
EOF

    chmod -R 777 /home/user
