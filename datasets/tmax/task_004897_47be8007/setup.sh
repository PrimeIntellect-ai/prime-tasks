#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate binding_data.csv
    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)
records = []
for _ in range(100):
    seq = "".join(random.choices(['A', 'C', 'G', 'T'], k=20))
    gc_count = seq.count('G') + seq.count('C')
    gc_frac = gc_count / 20.0

    noise = random.gauss(0, 0.05)
    score = 0.5 * gc_frac + 0.2 + noise
    records.append((seq, score))

with open('/home/user/binding_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['sequence', 'score'])
    for row in records:
        writer.writerow([row[0], f"{row[1]:.4f}"])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
