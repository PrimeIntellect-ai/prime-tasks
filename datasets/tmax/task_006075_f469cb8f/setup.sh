#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import json
import string
import numpy as np

os.makedirs('/home/user/datasets', exist_ok=True)

np.random.seed(42)
vocab = ["data", "science", "machine", "learning", "network", "neural", "deep", "analysis", "statistics", "regression", "classification", "clustering", "algorithm", "python", "model", "training", "evaluation", "metrics", "optimization", "dataset"]

embeddings = {word: np.random.uniform(-1, 1, 10).tolist() for word in vocab}
with open('/home/user/word_embeddings.json', 'w') as f:
    json.dump(embeddings, f)

with open('/home/user/query.txt', 'w') as f:
    f.write("Deep learning and neural network training optimization.")

# Generate datasets
datasets = []
for i in range(1, 21):
    # randomly pick 5-8 words
    words = np.random.choice(vocab, size=np.random.randint(5, 9), replace=True)
    text = " ".join(words) + "."
    filename = f"dataset_{i}.txt"
    with open(f'/home/user/datasets/{filename}', 'w') as f:
        f.write(text)
    datasets.append(filename)

# Subset (make them intentionally have some overlapping words with query)
subset = ["dataset_2.txt", "dataset_5.txt", "dataset_8.txt", "dataset_12.txt", "dataset_15.txt", "dataset_18.txt"]
with open('/home/user/subset.txt', 'w') as f:
    f.write("\n".join(subset))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
