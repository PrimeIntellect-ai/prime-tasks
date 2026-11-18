#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import csv
import random

random.seed(42)
with open('/home/user/dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'f1', 'text', 'label'])

    for i in range(100):
        # f1 generation
        if random.random() < 0.1:
            f1 = "NA"
        else:
            f1 = round(random.uniform(-5.0, 5.0), 2)

        # text (f2) generation
        word_count = random.randint(1, 25)
        text = " ".join(["word"] * word_count)

        # Determine label based on a hidden rule (e.g., 3*f1 - 1*f2 > 0)
        # We'll calculate a pseudo-label
        real_f1 = f1 if f1 != "NA" else 0.0
        score = 3.0 * real_f1 - 1.0 * word_count
        label = 1 if score > -5 else 0

        # Add some noise
        if random.random() < 0.1:
            label = 1 - label

        writer.writerow([i, f1, text, label])
EOF
    python3 /home/user/generate_data.py

    chmod -R 777 /home/user
