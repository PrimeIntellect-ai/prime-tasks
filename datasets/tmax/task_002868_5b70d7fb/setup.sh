#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(42)
bases = [
    "The quick brown fox jumps over the lazy dog.",
    "Data science is an interdisciplinary field.",
    "C++ is a high-performance programming language.",
    "Machine learning models require large datasets.",
    "A custom embedding space can be simulated easily."
]

with open("/home/user/data/raw_dataset.txt", "w") as f:
    for i in range(500):
        base = random.choice(bases)
        # Add random noise to create near-duplicates
        noise = "".join(random.choices("abcdefghijklmnopqrstuvwxyz ", k=random.randint(0, 5)))
        f.write(base + noise + "\n")
EOF

    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
