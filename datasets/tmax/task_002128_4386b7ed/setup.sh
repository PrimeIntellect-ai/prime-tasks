#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import random

os.makedirs('/home/user/raw_data', exist_ok=True)

for i in range(1, 51):
    target_sum = i * 1000.5

    # Deliberately corrupt samples 17 and 42 to fail validation
    if i in [17, 42]:
        target_sum += 5.0

    filename = f'/home/user/raw_data/sample_{i:03d}.txt'

    # Generate 50,000 floats that are prone to float accumulation errors
    # We use a mix of very large and very small numbers.
    random.seed(i)

    values = []
    for _ in range(10000):
        large_val = random.uniform(1e10, 1e11)
        values.append(large_val)
        values.append(-large_val)

    for _ in range(15000):
        noise = random.uniform(1e-1, 1e1)
        values.append((target_sum / 30000.0) + noise)
        values.append((target_sum / 30000.0) - noise)

    random.shuffle(values)

    with open(filename, 'w') as f:
        for val in values:
            f.write(f"{val:.12f}\n")
EOF

    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
