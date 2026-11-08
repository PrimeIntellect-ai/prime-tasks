#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import csv
import os

os.makedirs('/home/user', exist_ok=True)

data = [
    (1, "Doc A", "The quick brown fox jumps over the lazy dog."),
    (2, "Doc B", "Machine learning is fascinating and drives modern AI."),
    (3, "Doc C", "The quick brown fox jumped over the lazy dog."),
    (4, "Doc D", "Data science involves statistics, coding, and domain knowledge."),
    (5, "Doc E", "Cloud computing provides scalable resources on demand."),
    (6, "Doc F", "Artificial intelligence and machine learning are fascinating."),
    (7, "Doc G", "Cybersecurity is crucial for protecting sensitive data."),
    (8, "Doc H", "Data science needs statistics, coding, and domain expertise."),
    (9, "Doc I", "Software engineering practices ensure code quality."),
    (10, "Doc J", "Quantum computing uses quantum bits or qubits.")
]

with open('/home/user/dataset.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['doc_id', 'title', 'text'])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
