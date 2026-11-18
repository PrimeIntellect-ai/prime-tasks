#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

random.seed(42)
data_path = '/home/user/data.csv'

with open(data_path, 'w') as f:
    for i in range(1, 1001):
        token = f"tok_{i}"

        # Introduce "NaN" in about 10% of rows
        if random.random() < 0.1:
            x = "NaN" if random.random() < 0.33 else f"{random.uniform(-5, 5):.4f}"
            y = "NaN" if random.random() < 0.5 else f"{random.uniform(-5, 5):.4f}"
            z = "NaN" if random.random() < 0.5 else f"{random.uniform(-5, 5):.4f}"
            # ensure at least one NaN if chosen
            if x != "NaN" and y != "NaN" and z != "NaN":
                x = "NaN"
        else:
            x = f"{random.uniform(-5, 5):.4f}"
            y = f"{random.uniform(-5, 5):.4f}"
            z = f"{random.uniform(-5, 5):.4f}"

        f.write(f"{i},{token},{x},{y},{z}\n")

os.chmod(data_path, 0o644)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
