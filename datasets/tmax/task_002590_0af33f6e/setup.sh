#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/model_outputs', exist_ok=True)

random.seed(42)
words = ['apple', 'banana', 'cherry', 'date', 'elderberry', 'fig', 'grape', 'honeydew', 'kiwi', 'lemon']

def generate_text(num_words):
    return ' '.join(random.choices(words, k=num_words))

# Generate 99 normal files
for i in range(100):
    if i == 73:
        # Anomaly file: lots of 'z's which have ascii 122. 
        # "zzzz" ascii sum = 488 (even, %3 = 2). 
        # "zzz" ascii sum = 366 (even, %3 = 0).
        content = ' '.join(['zzz'] * 500)
    else:
        content = generate_text(random.randint(50, 150))

    with open(f'/home/user/model_outputs/output_{i:02d}.txt', 'w') as f:
        f.write(content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
