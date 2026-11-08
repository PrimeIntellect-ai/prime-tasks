#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

def read_csv(filepath):
    data = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                data.append([float(x) for x in line.split(',')])
    return data

def compute_expected_top3():
    raw_data = read_csv('/home/user/raw_items.csv')
    num_rows = len(raw_data)
    num_cols = len(raw_data[0])

    clean_data = [[0.0] * num_cols for _ in range(num_rows)]

    for c in range(num_cols):
        valid_vals = []
        for r in range(num_rows):
            val = raw_data[r][c]
            if val != -999.0:
                valid_vals.append(val)

        n = len(valid_vals)
        mean = sum(valid_vals) / n
        variance = sum((x - mean) ** 2 for x in valid_vals) / n
        std = math.sqrt(variance)

        lower_bound = mean - 3 * std
        upper_bound = mean + 3 * std

        for r in range(num_rows):
            val = raw_data[r][c]
            if val == -999.0:
                val = mean
            if val < lower_bound:
                val = lower_bound
            elif val > upper_bound:
                val = upper_bound
            clean_data[r][c] = val

    proj = [
        [ 0.5, -0.2,  0.1],
        [-0.1,  0.6,  0.3],
        [ 0.4,  0.4, -0.5],
        [-0.3,  0.1,  0.8],
        [ 0.2, -0.7,  0.2]
    ]

    embeddings = []
    for r in range(num_rows):
        emb = [0.0, 0.0, 0.0]
        for j in range(3):
            for k in range(5):
                emb[j] += clean_data[r][k] * proj[k][j]
        embeddings.append(emb)

    dists = []
    emb0 = embeddings[0]
    for r in range(1, num_rows):
        emb = embeddings[r]
        dist = math.sqrt(sum((emb[j] - emb0[j]) ** 2 for j in range(3)))
        dists.append((dist, r))

    dists.sort(key=lambda x: x[0])
    top3 = [x[1] for x in dists[:3]]
    return top3

def test_embeddings_file_exists():
    assert os.path.exists('/home/user/clean_embeddings.csv'), "The file /home/user/clean_embeddings.csv was not created."
    assert os.path.exists('/home/user/top3_similar.txt'), "The file /home/user/top3_similar.txt was not created."

def test_top3_similar_correctness():
    top3_file = '/home/user/top3_similar.txt'
    assert os.path.exists(top3_file), f"{top3_file} does not exist."

    with open(top3_file, 'r') as f:
        content = f.read().strip()

    assert content, f"{top3_file} is empty."

    try:
        student_top3 = [int(x.strip()) for x in content.split(',')]
    except ValueError:
        assert False, f"Could not parse integers from {top3_file}. Content was: {content}"

    expected_top3 = compute_expected_top3()

    assert student_top3 == expected_top3, f"Expected top 3 neighbors {expected_top3}, but got {student_top3}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
