#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

os.makedirs('/home/user', exist_ok=True)

# Generate synthetic dataset
random.seed(42)
words_pos = ["error", "fail", "critical", "timeout", "crash", "system", "down", "alert"]
words_neg = ["success", "ok", "user", "login", "normal", "system", "up", "info"]

with open('/home/user/dataset.tsv', 'w') as f:
    f.write("label\ttext\n")
    for _ in range(50):
        # Generate positive samples (label 1)
        text_words = random.sample(words_pos, k=random.randint(2, 5)) + random.sample(["the", "a", "in", "on"], k=2)
        random.shuffle(text_words)
        f.write(f"1\t{' '.join(text_words).capitalize()}.\n")

        # Generate negative samples (label 0)
        text_words = random.sample(words_neg, k=random.randint(2, 5)) + random.sample(["the", "a", "in", "on"], k=2)
        random.shuffle(text_words)
        f.write(f"0\t{' '.join(text_words).capitalize()}!\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
