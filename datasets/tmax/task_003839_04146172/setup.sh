#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak g++
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    espeak -w /app/lab_notes.wav "For the new assay, target a Wallace melting temperature between sixty and sixty-six degrees. Ensure no sequence has a homopolymer run of more than three bases, meaning four of the same base in a row is an instant rejection."

    cat << 'EOF' > /tmp/gen_corpus.py
import os

clean = [
    "GCTAGCTAGCTAGCTAGCTA",
    "GCTAGCTAGCTAGCTAGCTAA",
    "GCTAGCTAGCTAGCTAGCTAAT",
    "GCTAGCTAGCTAGCTAGCTAGC"
]

evil = [
    "GCTAGCTAGCTAGCTAGCT",
    "GCTAGCTAGCTAGCTAGCTAGCTAG",
    "GCGCGCGCGCGCGCGCGCGC",
    "ATATATATATATATATATAT",
    "GCTAGCTAGCTAGCAAAAGC"
]

for i, seq in enumerate(clean):
    with open(f"/app/corpus/clean/seq_{i}.fasta", "w") as f:
        f.write(f">clean_{i}\n{seq}\n")

for i, seq in enumerate(evil):
    with open(f"/app/corpus/evil/seq_{i}.fasta", "w") as f:
        f.write(f">evil_{i}\n{seq}\n")
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
