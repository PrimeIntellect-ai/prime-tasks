#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import re
import math

def tokenize(text):
    text = re.sub(r'[^a-z0-9\s]', '', text.lower())
    return [t for t in text.split() if t]

def train_nb(data, alpha):
    vocab = set()
    for row in data:
        vocab.update(row['tokens'])

    V = len(vocab)
    counts = {0: {}, 1: {}}
    N = {0: 0, 1: 0}

    for row in data:
        c = row['spam']
        for t in row['tokens']:
            counts[c][t] = counts[c].get(t, 0) + 1
            N[c] += 1

    return counts, N, V, vocab

def predict_nb(tokens, counts, N, V, alpha):
    p0 = 0.0
    p1 = 0.0

    for t in tokens:
        p0 += math.log((counts[0].get(t, 0) + alpha) / (N[0] + alpha * V))
        p1 += math.log((counts[1].get(t, 0) + alpha) / (N[1] + alpha * V))

    return 1 if p1 > p0 else 0

def test_features_json():
    features_path = '/home/user/features.json'
    assert os.path.exists(features_path), f"File {features_path} does not exist."
    assert os.path.isfile(features_path), f"Path {features_path} is not a file."

    with open(features_path, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {features_path} is not valid JSON."

    assert "best_alpha" in result, "Missing 'best_alpha' in JSON."
    assert "top_5_tokens" in result, "Missing 'top_5_tokens' in JSON."

    csv_path = '/home/user/emails.csv'
    data = []
    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                'id': int(row['id']),
                'text': row['text'],
                'spam': int(row['spam']),
                'tokens': tokenize(row['text'])
            })

    alphas = [0.1, 0.5, 1.0, 2.0, 5.0]
    best_alpha = None
    best_acc = -1

    n_splits = 5
    fold_size = len(data) // n_splits

    for alpha in alphas:
        accs = []
        for i in range(n_splits):
            test_start = i * fold_size
            test_end = test_start + fold_size if i < n_splits - 1 else len(data)

            test_data = data[test_start:test_end]
            train_data = data[:test_start] + data[test_end:]

            counts, N, V, vocab = train_nb(train_data, alpha)

            correct = 0
            for row in test_data:
                pred = predict_nb(row['tokens'], counts, N, V, alpha)
                if pred == row['spam']:
                    correct += 1
            accs.append(correct / len(test_data))

        avg_acc = sum(accs) / len(accs)
        if avg_acc > best_acc:
            best_acc = avg_acc
            best_alpha = alpha

    counts, N, V, vocab = train_nb(data, best_alpha)

    llrs = []
    for t in vocab:
        p0 = (counts[0].get(t, 0) + best_alpha) / (N[0] + best_alpha * V)
        p1 = (counts[1].get(t, 0) + best_alpha) / (N[1] + best_alpha * V)
        llr = abs(math.log(p1) - math.log(p0))
        llrs.append((t, llr))

    llrs.sort(key=lambda x: (-x[1], x[0]))
    top_5 = [x[0] for x in llrs[:5]]

    assert math.isclose(result["best_alpha"], best_alpha, rel_tol=1e-5), f"Expected best_alpha {best_alpha}, got {result['best_alpha']}"
    assert result["top_5_tokens"] == top_5, f"Expected top_5_tokens {top_5}, got {result['top_5_tokens']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
