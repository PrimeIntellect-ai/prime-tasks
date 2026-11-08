#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest matplotlib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import random

def setup_task():
    random.seed(123)
    os.makedirs('/home/user', exist_ok=True)

    N = 50
    with open('/home/user/network_data.txt', 'w') as f:
        f.write(f"{N}\n")
        for _ in range(N):
            V = random.randint(10, 20)
            E = random.randint(15, 30)
            f.write(f"{V} {E}\n")
            for _ in range(E):
                u = random.randint(0, V-1)
                v = random.randint(0, V-1)
                while u == v:
                    v = random.randint(0, V-1)
                w = random.randint(1, 100)
                f.write(f"{u} {v} {w}\n")

if __name__ == '__main__':
    setup_task()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
