#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc
    pip3 install pytest

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/embed.py
import sys
import json

def get_embedding(text):
    text = text.strip()
    length = len(text) / 100.0
    words = len(text.split()) / 20.0
    vowels = sum(1 for c in text.lower() if c in "aeiou") / 50.0
    consonants = sum(1 for c in text.lower() if c in "bcdfghjklmnpqrstvwxyz") / 50.0
    ascii_sum = sum(ord(c) for c in text) % 10 / 10.0
    return [round(length, 3), round(words, 3), round(vowels, 3), round(consonants, 3), round(ascii_sum, 3)]

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(json.dumps(get_embedding(sys.argv[1])))
EOF
    chmod +x /home/user/embed.py

    echo "Gene expression data from human liver cells." > /home/user/datasets/dataset_A.txt
    echo "Historical weather records from the 19th century." > /home/user/datasets/dataset_B.txt
    echo "Single-cell RNA sequencing of mice." > /home/user/datasets/dataset_C.txt
    echo "Stock market prices for tech companies." > /home/user/datasets/dataset_D.txt
    echo "Genomic sequencing data of agricultural crops." > /home/user/datasets/dataset_E.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
