#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import json
import random
import os

random.seed(42)
os.makedirs('/home/user', exist_ok=True)

words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "data", "science", "machine", "learning", "token", "bpe", "neural", "network", "transformer", "attention", "layer", "model"]

with open('/home/user/raw_data.jsonl', 'w') as f:
    for i in range(1, 1001):
        # Generate random length text
        length = random.randint(5, 50)
        text = " ".join(random.choices(words, k=length))
        f.write(json.dumps({"id": i, "text": text}) + "\n")
EOF

    python3 /tmp/gen_data.py

    chmod -R 777 /home/user
