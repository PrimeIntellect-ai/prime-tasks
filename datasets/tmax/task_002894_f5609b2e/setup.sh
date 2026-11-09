#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libomp-dev
    pip3 install pytest

    mkdir -p /home/user

    python3 -c "
import random
import os

os.makedirs('/home/user', exist_ok=True)
random.seed(42)

with open('/home/user/init.txt', 'w') as f:
    for _ in range(1000):
        x = random.uniform(-5, 5)
        y = random.uniform(-5, 5)
        f.write(f'{x:.6f} {y:.6f}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
