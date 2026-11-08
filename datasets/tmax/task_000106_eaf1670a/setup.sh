#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        git \
        wget \
        curl \
        espeak \
        ffmpeg \
        gawk \
        bc

    pip3 install pytest pandas numpy

    mkdir -p /app
    mkdir -p /home/user

    # Generate query.wav
    espeak -w /tmp/temp.wav "find the latest financial reports"
    ffmpeg -i /tmp/temp.wav -ar 16000 -ac 1 -c:a pcm_s16le /app/query.wav
    rm /tmp/temp.wav

    # Create vocab.csv and documents.csv
    python3 -c "
import csv
import random
import numpy as np

# vocab.csv
vocab = {
    'find': [0.1, 0.2, -0.1, 0.5, 0.0],
    'the': [0.0, 0.0, 0.0, 0.0, 0.0],
    'latest': [0.5, 0.1, 0.8, -0.2, 0.3],
    'financial': [-0.4, 0.7, 0.2, 0.1, 0.6],
    'reports': [0.2, 0.3, 0.5, 0.4, 0.1]
}
with open('/app/vocab.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for word, vec in vocab.items():
        writer.writerow([word] + vec)

# documents.csv
query_vec = np.array([0.4, 1.3, 1.4, 0.8, 1.0])
truth_top = {'doc_12', 'doc_45', 'doc_78', 'doc_91', 'doc_23', 'doc_56', 'doc_89', 'doc_34', 'doc_67', 'doc_99'}

with open('/app/documents.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for i in range(1, 101):
        doc_id = f'doc_{i}'
        if doc_id in truth_top:
            # High similarity
            vec = query_vec + np.random.normal(0, 0.05, 5)
        else:
            # Random vector
            vec = np.random.normal(0, 1, 5)
        writer.writerow([doc_id] + list(np.round(vec, 4)))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
