#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy
    pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup_data.py
import json
import random

random.seed(123)
vocab = {f"word_{i}": i for i in range(1000)}
vocab["<unk>"] = 1000

# Generate corpus
words = [f"word_{random.randint(0, 999)}" for _ in range(50000)]
with open("/home/user/corpus.txt", "w") as f:
    f.write(" ".join(words))

with open("/home/user/vocab.json", "w") as f:
    json.dump(vocab, f)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
