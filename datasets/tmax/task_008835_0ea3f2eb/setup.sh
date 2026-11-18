#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest scikit-learn numpy pandas joblib

    mkdir -p /home/user/data
    mkdir -p /home/user/models

    cat << 'EOF' > /home/user/create_data.py
import json
import random

words = ["fast", "slow", "great", "terrible", "battery", "screen", "support", "price", "value", "quality", "refund", "recommend", "app", "crash", "update"]
with open('/home/user/data/raw.jsonl', 'w') as f:
    for i in range(1000):
        text = " ".join(random.choices(words, k=random.randint(5, 20)))
        f.write(json.dumps({"id": i, "text": text}) + "\n")
EOF

    python3 /home/user/create_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
