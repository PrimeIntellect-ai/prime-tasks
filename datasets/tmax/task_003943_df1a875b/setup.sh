#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy

    mkdir -p /home/user

    python3 -c "
import os
import csv

csv_path = '/home/user/raw_texts.csv'

texts = [
    'Hello world!',
    'Machine learning is fun.',
    'Tokenization, correlation, and stats-are-great.',
    'A B C D E F G',
    'Hypothesis testing validates our assumptions.',
    'This is a test sentence with punctuation!!!',
    'Data science requires robust data-prep pipelines.',
    'One-two-three four-five.',
    'NoPunctuationHere',
    'Lots of spaces     in this one.',
    'Let\'s evaluate the t-statistic!'
]

with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'text'])
    for i, t in enumerate(texts):
        writer.writerow([i+1, t])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
