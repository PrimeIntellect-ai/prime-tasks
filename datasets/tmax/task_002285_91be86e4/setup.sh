#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    python3 -c '
import random
import csv

random.seed(42)
categories = ["News", "Sports", "Entertainment", "Tech"]
words = ["apple", "banana", "cat", "dog", "elephant", "fish", "grape", "hello", "igloo", "jump"]

with open("/home/user/dataset.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "category", "text"])
    for i in range(1, 101):
        cat = categories[i % 4]
        bias_word = words[i % 4]
        text_words = [random.choice(words) for _ in range(5)] + [bias_word] * 3
        random.shuffle(text_words)
        writer.writerow([i, cat, " ".join(text_words)])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
