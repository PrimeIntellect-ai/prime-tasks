#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random
import math

random.seed(42)

with open("/home/user/embeddings.csv", "w", newline="") as f:
    writer = csv.writer(f)
    for i in range(1, 101):
        # Generate some synthetic embeddings
        x1 = random.uniform(0, 2)
        x2 = random.uniform(0, 2)
        x3 = random.uniform(0, 2)

        # True distance
        dist = math.sqrt((x1-1)**2 + (x2-1)**2 + (x3-1)**2)

        # Label generation based on a specific alpha (let's say optimal is around 0.5)
        # S = exp(-dist) * 0.5
        score = math.exp(-dist) * 0.5
        label = 1 if score > 0.1 else 0

        # Add some noise
        if random.random() < 0.1:
            label = 1 - label

        writer.writerow([i, round(x1, 4), round(x2, 4), round(x3, 4), label])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
