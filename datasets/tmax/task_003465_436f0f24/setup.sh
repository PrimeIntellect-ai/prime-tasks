#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv

os.makedirs('/home/user', exist_ok=True)

golden_data = [
    {"id": 1, "text": "The quick brown fox jumps over the lazy dog"},
    {"id": 2, "text": "Machine learning models require careful validation"},
    {"id": 3, "text": "Data science involves statistics and programming"}
]

exp_A_data = [
    {"id": 1, "text": "The quick brown fox jumps over the lazy dog"},
    {"id": 2, "text": "Machine learning requires careful validation"},
    {"id": 3, "text": "Statistics and programming in data science"},
    {"id": 4, "text": "Random text that does not match anything"},
    {"id": 5, "text": "Data science and programming"}
]

exp_B_data = [
    {"id": 1, "text": "The quick brown fox jumps"},
    {"id": 2, "text": "Completely unrelated output text"},
    {"id": 3, "text": "Another completely random output"},
    {"id": 4, "text": "Machine learning is cool"}
]

for filename, data in [('golden.csv', golden_data), ('exp_A.csv', exp_A_data), ('exp_B.csv', exp_B_data)]:
    with open(f'/home/user/{filename}', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['id', 'text'])
        writer.writeheader()
        writer.writerows(data)
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
