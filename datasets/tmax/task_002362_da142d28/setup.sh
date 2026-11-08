#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar gcc make time
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the datasets
    mkdir -p /home/user/dataset
    cat << 'EOF' > /home/user/generate_data.py
import csv
import json
import random

random.seed(42)
num_papers = 100000
num_edges = 500000

# Generate papers.csv
with open('/home/user/dataset/papers.csv', 'w') as f:
    for i in range(1, num_papers + 1):
        year = random.randint(2000, 2023)
        f.write(f"{i},Paper_Title_{i},{year}\n")

# Generate citations.txt
with open('/home/user/dataset/citations.txt', 'w') as f:
    for _ in range(num_edges):
        src = random.randint(1, num_papers)
        tgt = random.randint(1, num_papers)
        if src != tgt:
            f.write(f"{src} {tgt}\n")

# Generate metadata.json
metadata = []
vocab = ["AI", "Graph", "DB", "SQL", "C", "Systems", "Network", "Security"]
for i in range(1, num_papers + 1):
    kws = random.sample(vocab, random.randint(1, 4))
    metadata.append({"id": i, "keywords": kws})

with open('/home/user/dataset/metadata.json', 'w') as f:
    json.dump(metadata, f)
EOF
    python3 /home/user/generate_data.py

    # Download and perturb cJSON
    mkdir -p /app/
    curl -sL https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz | tar xz -C /app/
    sed -i 's/CC = gcc/CC = gec/g' /app/cJSON-1.7.15/Makefile

    chmod -R 777 /home/user
    chmod -R 777 /app
