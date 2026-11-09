#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest numpy

    # Download and extract annoy-1.17.3
    mkdir -p /app
    cd /app
    wget https://github.com/spotify/annoy/archive/refs/tags/v1.17.3.tar.gz -O annoy.tar.gz
    tar -xzf annoy.tar.gz
    rm annoy.tar.gz

    # Generate data and modify setup.py
    python3 -c '
import os
import numpy as np
import re

os.makedirs("/app/data", exist_ok=True)
os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

def generate_vectors(n):
    v = np.random.randn(n, 128)
    v = v / np.linalg.norm(v, axis=1, keepdims=True)
    return v

test_v = generate_vectors(1000)
with open("/app/data/test_set_embeddings.csv", "w") as f:
    for i in range(1000):
        row = [f"test_{i}"] + [str(x) for x in test_v[i]]
        f.write(",".join(row) + "\n")

for i in range(10):
    clean_v = generate_vectors(500)
    with open(f"/app/corpus/clean/file_{i}.csv", "w") as f:
        for j in range(500):
            row = [f"clean_{i}_{j}"] + [str(x) for x in clean_v[j]]
            f.write(",".join(row) + "\n")

    evil_v = generate_vectors(499)
    evil_base = test_v[np.random.randint(0, 1000)]
    noise = np.random.randn(128) * 0.001
    evil_vec = evil_base + noise
    evil_vec = evil_vec / np.linalg.norm(evil_vec)

    with open(f"/app/corpus/evil/file_{i}.csv", "w") as f:
        for j in range(499):
            row = [f"evil_{i}_{j}"] + [str(x) for x in evil_v[j]]
            f.write(",".join(row) + "\n")
        row = [f"evil_leak_{i}"] + [str(x) for x in evil_vec]
        f.write(",".join(row) + "\n")

setup_path = "/app/annoy-1.17.3/setup.py"
with open(setup_path, "r") as f:
    content = f.read()

# Replace ext_modules list with an empty list
content = re.sub(r"ext_modules=\[.*?\],", "ext_modules=[],", content, flags=re.DOTALL)

with open(setup_path, "w") as f:
    f.write(content)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
