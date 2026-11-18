#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/solver.py
import sys
sys.setrecursionlimit(50000)

def calculate_decay_path(x):
    # Bug: Exact floating point comparison
    if x == 0.0:
        return [0.0]

    # Recursively calculate the rest of the path
    path = calculate_decay_path(x - 0.1)
    path.insert(0, x)
    return path

if __name__ == "__main__":
    if len(sys.argv) > 1:
        val = float(sys.argv[1])
        try:
            result = calculate_decay_path(val)
            print(len(result))
        except Exception as e:
            print(f"Error: {e}")
            sys.exit(1)
EOF

    chmod +x /home/user/service/solver.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
