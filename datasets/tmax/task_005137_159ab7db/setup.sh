#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import random

os.makedirs('/home/user', exist_ok=True)

words = {
    "the": 0.1, "quick": 0.05, "brown": 0.05, "fox": 0.05,
    "jumps": 0.05, "over": 0.05, "lazy": 0.05, "dog": 0.05,
    "hello": 0.05, "world": 0.05, "data": 0.1, "science": 0.1,
    "bayesian": 0.05, "inference": 0.05, "bootstrap": 0.05,
    "sampling": 0.05, "machine": 0.05, "learning": 0.05
}

def add_noise(word):
    if random.random() < 0.3:
        idx = random.randint(0, len(word)-1)
        return word[:idx] + random.choice('abcdefghijklmnopqrstuvwxyz') + word[idx+1:]
    return word

random.seed(42)
sentences = []
for _ in range(100):
    length = random.randint(5, 10)
    sentence = [random.choices(list(words.keys()), weights=list(words.values()))[0] for _ in range(length)]
    noisy = [add_noise(w) for w in sentence]
    sentences.append(" ".join(noisy))

with open('/home/user/raw_texts.txt', 'w') as f:
    for s in sentences:
        f.write(s + "\n")

with open('/home/user/word_priors.csv', 'w') as f:
    f.write("word,prior\n")
    for w, p in words.items():
        f.write(f"{w},{p}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
