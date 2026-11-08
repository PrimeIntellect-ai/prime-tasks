#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import numpy as np

random.seed(42)
np.random.seed(42)

with open("/home/user/raw.tsv", "w", newline="") as f:
    writer = csv.writer(f, delimiter='\t')
    # Generate 10,000 rows
    for i in range(10000):
        user_id = f"U{random.randint(100, 999)}"
        item_id = f"I{random.randint(1000, 9999)}"
        # Add some dirty ratings
        if random.random() < 0.05:
            rating = random.choice([0, 6, 10, -1])
        else:
            rating = random.randint(1, 5)

        # Generate latencies
        if random.random() < 0.05:
            latency = random.uniform(0.1, 9.9) # Too fast
        elif random.random() < 0.05:
            latency = random.uniform(5000.1, 10000.0) # Too slow
        else:
            if rating >= 4:
                latency = np.random.normal(250.0, 50.0)
            else:
                latency = np.random.normal(300.0, 80.0)

        # Format latency to 4 decimal places
        writer.writerow([user_id, item_id, rating, f"{latency:.4f}"])
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
