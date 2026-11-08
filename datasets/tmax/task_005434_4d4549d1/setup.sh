#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user', exist_ok=True)

random.seed(42)
bases = [
    "Analysis of {subject} using {method}.",
    "Dataset containing {subject} collected via {method}.",
    "A comprehensive study of {subject} over 10 years."
]
subjects = ["neural networks", "quantum computing", "marine biology", "financial markets", "climate change"]
methods = ["satellite imagery", "spectroscopy", "time series analysis", "randomized trials", "deep learning"]

lines = []
for i in range(1, 151):
    text = random.choice(bases).format(subject=random.choice(subjects), method=random.choice(methods))
    lines.append(f"D{i:03d}|{text}\n")

# Inject ground truth top pair
lines.append("D998|Comprehensive dataset containing high-resolution satellite imagery of the Amazon rainforest collected over 10 years.\n")
lines.append("D999|Comprehensive dataset containing high-resolution satellite imagery of the African savanna collected over 10 years.\n")

with open('/home/user/descriptions.txt', 'w') as f:
    f.writelines(lines)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
