#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import csv
import json
import random

# Generate dataset.csv
random.seed(42)
with open('/home/user/dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'f1', 'f2', 'f3', 'f4'])
    for i in range(1, 10001):
        f1 = random.uniform(-5.0, 5.0)
        f2 = random.uniform(-5.0, 5.0)
        f3 = random.uniform(-5.0, 5.0)
        f4 = random.uniform(-5.0, 5.0)
        writer.writerow([i, round(f1, 4), round(f2, 4), round(f3, 4), round(f4, 4)])

# Generate weights.json
weights = {
    "weights": [0.5, -1.2, 3.4, 0.8],
    "bias": -0.5
}
with open('/home/user/weights.json', 'w') as f:
    json.dump(weights, f, indent=2)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
