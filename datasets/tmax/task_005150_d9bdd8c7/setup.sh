#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

os.makedirs('/home/user', exist_ok=True)

random.seed(42)
with open('/home/user/spectra.csv', 'w') as f:
    f.write('id,fold,x,y\n')
    for i in range(150):
        fold = (i % 3) + 1
        x = random.uniform(0, 10)
        # y is a nonlinear function of x with some noise
        y = 3.0 * x + 1.5 * (x ** 2) + random.gauss(0, 2.0)
        f.write(f'{i},{fold},{x:.4f},{y:.4f}\n')
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
