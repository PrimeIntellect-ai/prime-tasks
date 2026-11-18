#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the initial points.csv dataset
    python3 -c "
import random
import os

os.makedirs('/home/user', exist_ok=True)
random.seed(42)
with open('/home/user/points.csv', 'w') as f:
    for _ in range(950):
        x = random.gauss(10.0, 2.0)
        y = random.gauss(5.0, 2.0)
        f.write(f'{x:.6f},{y:.6f}\n')
    for _ in range(50):
        x = random.gauss(10.0, 15.0)
        y = random.gauss(5.0, 15.0)
        f.write(f'{x:.6f},{y:.6f}\n')
"

    chmod -R 777 /home/user
