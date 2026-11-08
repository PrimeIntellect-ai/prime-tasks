#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cat << 'EOF' > /home/user/pipeline/reference.py
def evaluate_constraints(v1: int, v2: int, v3: int, v4: int) -> int:
    c1 = (3 * v1 + 5 * v2 + v3 - 2 * v4) == 99
    c2 = (v1 * v1 + v2 * v3 - v4) == 283
    c3 = (v1 + v2 + v3 + v4) == 48
    if c1 and c2 and c3:
        return 1
    return 0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
