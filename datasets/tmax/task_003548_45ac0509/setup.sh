#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import random

random.seed(42)
os.makedirs('/home/user', exist_ok=True)

with open('/home/user/raw_data.csv', 'w') as f:
    for i in range(100000):
        row = [round(random.uniform(-1.0, 1.0), 4) for _ in range(10)]
        f.write(','.join(map(str, row)) + '\n')
"

    chmod -R 777 /home/user
