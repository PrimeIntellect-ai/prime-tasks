#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

def test_top_docs_output():
    vocab_path = '/home/user/model/vocab.json'
    projection_path = '/home/user/model/projection.csv'
    data_dir = '/home/user/etl_data'
    output_path = '/home/user/top_docs.txt'

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    # Load vocab
    with open(vocab_path, 'r') as f:
        vocab = json.load(f)

    # Load projection matrix
    projection = []
    with open(projection_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                projection.append([float(x) for x in row])

    # Process documents
    query = [0.85, -0.15]
    results = []

    for filename in os.listdir(data_dir):
        if not filename.endswith('.txt'):
            continue

        with open(os.path.join(data_dir, filename), 'r') as f:
            content = f.read()

        words = content.split()
        known_words = [w for w in words if w in vocab]

        if not known_words:
            doc_emb = [0.0] * 5
        else:
            doc_emb = [0.0] * 5
            for w in known_words:
                for i in range(5):
                    doc_emb[i] += vocab[w][i]
            doc_emb = [x / len(known_words) for x in doc_emb]

        reduced = [0.0, 0.0]
        for j in range(2):
            for i in range(5):
                reduced[j] += doc_emb[i] * projection[i][j]

        dist = math.sqrt((reduced[0] - query[0])**2 + (reduced[1] - query[1])**2)
        results.append((dist, filename))

    # Sort by distance, then filename
    results.sort(key=lambda x: (x[0], x[1]))
    expected_top_3 = [x[1] for x in results[:3]]

    # Read actual output
    with open(output_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 3, f"Expected exactly 3 lines in {output_path}, but got {len(actual_lines)}."

    for i in range(3):
        assert actual_lines[i] == expected_top_3[i], f"Mismatch at rank {i+1}: expected {expected_top_3[i]}, got {actual_lines[i]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
