#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask celery redis

    mkdir -p /app/services/gateway
    mkdir -p /app/services/worker

    cat << 'EOF' > /app/legacy_kmer_dist
#!/usr/bin/env python3
import sys
import math
import itertools

def get_kmer_counts(seq):
    kmers = [''.join(p) for p in itertools.product('ACGT', repeat=3)]
    counts = {k: 1 for k in kmers}
    for i in range(len(seq) - 2):
        kmer = seq[i:i+3]
        if kmer in counts:
            counts[kmer] += 1
    return counts

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    seq1, seq2 = sys.argv[1], sys.argv[2]
    c1 = get_kmer_counts(seq1)
    c2 = get_kmer_counts(seq2)

    sum1 = sum(c1.values())
    sum2 = sum(c2.values())

    dist = 0.0
    kmers = [''.join(p) for p in itertools.product('ACGT', repeat=3)]
    for k in kmers:
        v1 = c1[k] / sum1
        v2 = c2[k] / sum2
        dist += (v1 - v2) ** 2

    print(f"{math.sqrt(dist):.6f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/legacy_kmer_dist

    cat << 'EOF' > /app/services/gateway/app.py
from flask import Flask, request, jsonify
from celery import Celery

app = Flask(__name__)
# TODO: Fix broker and backend URLs
celery_app = Celery('tasks', broker='redis://invalid_host:6379/0', backend='redis://invalid_host:6379/0')

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.json
    seq1 = data.get('seq1')
    seq2 = data.get('seq2')
    # TODO: Call celery task and return result
    return jsonify({"error": "Not implemented"}), 501

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

    cat << 'EOF' > /app/services/worker/tasks.py
from celery import Celery
import subprocess

app = Celery('tasks', broker='redis://localhost:6379/0', backend='redis://localhost:6379/0')

@app.task(name='tasks.compute_kmer_dist')
def compute_kmer_dist(seq1, seq2):
    # TODO: Shell out to /home/user/kmer_dist.py
    pass
EOF

    cat << 'EOF' > /app/services/docker-compose.yml
version: '3'
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
  gateway:
    build: ./gateway
    ports:
      - "8000:8000"
    depends_on:
      - redis
  worker:
    build: ./worker
    depends_on:
      - redis
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
