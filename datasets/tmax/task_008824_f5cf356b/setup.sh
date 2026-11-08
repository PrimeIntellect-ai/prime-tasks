#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy
    pip3 install pytest

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/setup_data.py
import os
import random

random.seed(123)
vocab = ["server", "error", "timeout", "success", "connection", "refused", "database", "query", "failed", "user", "login", "auth", "null", "pointer", "exception"]

os.makedirs("/home/user/raw_data", exist_ok=True)

for i in range(50):
    num_words = random.randint(10, 50)
    words = [random.choice(vocab) for _ in range(num_words)]
    # Add some punctuation
    words = [w + random.choice(['', '.', ',', '!', '?']) for w in words]
    content = " ".join(words)
    with open(f"/home/user/raw_data/log_{i:02d}.txt", "w") as f:
        f.write(content)
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
