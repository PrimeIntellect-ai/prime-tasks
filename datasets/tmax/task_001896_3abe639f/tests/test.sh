#!/bin/bash
set +e
mkdir -p /logs/verifier
score=1

SRC=/home/user/src/pipeline.cpp
BIN=/tmp/submitted_pipeline
DATA=/home/user/data/dataset.csv
RESULTS=/home/user/results.json
DATA_BACKUP=/tmp/verifier_dataset_original.csv
ORIGINAL_RESULTS=/tmp/verifier_original_results.json

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import pytest

def load_data(filepath):
    X = []
    y = []
    with open(filepath, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            X.append([float(v) for v in parts[:-1]])
            y.append(int(float(parts[-1])))
    return X, y

def mean_std(X):
    n = len(X)
    n_features = len(X[0])
    means = [sum(X[i][j] for i in range(n)) / n for j in range(n_features)]
    stds = []
    for j in range(n_features):
        var = sum((X[i][j] - means[j]) ** 2 for i in range(n)) / n
        std = math.sqrt(var)
        stds.append(std if std != 0 else 1.0)
    return means, stds

def transform(X, means, stds):
    return [[(row[j] - means[j]) / stds[j] for j in range(len(row))] for row in X]

def euclidean_distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))

def knn_predict(X_train, y_train, X_test, k):
    preds = []
    for test_pt in X_test:
        dists = [(euclidean_distance(test_pt, train_pt), i) for i, train_pt in enumerate(X_train)]
        dists.sort()

        counts = {}
        for _, idx in dists[:k]:
            label = y_train[idx]
            counts[label] = counts.get(label, 0) + 1

        best_label = -1
        max_count = -1
        for _, idx in dists[:k]:
            label = y_train[idx]
            if counts[label] > max_count:
                max_count = counts[label]
                best_label = label
        preds.append(best_label)
    return preds

def compute_expected_results():
    X, y = load_data('/home/user/data/dataset.csv')
    n = len(X)
    folds = 5
    fold_size = n // folds

    best_k = 1
    best_acc = -1.0

    for k in [1, 3, 5, 7, 9]:
        total_acc = 0.0
        for i in range(folds):
            test_start = i * fold_size
            test_end = (i + 1) * fold_size

            X_test = X[test_start:test_end]
            y_test = y[test_start:test_end]
            X_train = X[:test_start] + X[test_end:]
            y_train = y[:test_start] + y[test_end:]

            means, stds = mean_std(X_train)
            X_train_scaled = transform(X_train, means, stds)
            X_test_scaled = transform(X_test, means, stds)

            preds = knn_predict(X_train_scaled, y_train, X_test_scaled, k)
            correct = sum(1 for p, true_y in zip(preds, y_test) if p == true_y)
            total_acc += correct / len(y_test)

        avg_acc = total_acc / folds
        if avg_acc > best_acc:
            best_acc = avg_acc
            best_k = k

    means, stds = mean_std(X)
    X_scaled = transform(X, means, stds)

    new_point = [1.5, 2.0, -1.0, 0.5]
    new_point_scaled = transform([new_point], means, stds)[0]

    dists = [(euclidean_distance(new_point_scaled, pt), i) for i, pt in enumerate(X_scaled)]
    dists.sort()

    neighbors = [idx for _, idx in dists[:3]]

    counts = {}
    for _, idx in dists[:best_k]:
        label = y[idx]
        counts[label] = counts.get(label, 0) + 1

    best_label = -1
    max_count = -1
    for _, idx in dists[:best_k]:
        label = y[idx]
        if counts[label] > max_count:
            max_count = counts[label]
            best_label = label

    return best_k, best_acc, best_label, neighbors

def test_results_json():
    results_path = '/home/user/results.json'
    assert os.path.isfile(results_path), f'File {results_path} is missing.'

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('results.json is not a valid JSON file.')

    expected_k, expected_acc, expected_pred, expected_neighbors = compute_expected_results()

    assert 'best_k' in results, "Missing 'best_k' in results."
    assert results['best_k'] == expected_k, f"Expected best_k={expected_k}, got {results['best_k']}"

    assert 'best_cv_accuracy' in results, "Missing 'best_cv_accuracy' in results."
    assert abs(results['best_cv_accuracy'] - expected_acc) < 1e-4, f"Expected best_cv_accuracy ~ {expected_acc}, got {results['best_cv_accuracy']}"

    assert 'new_point_prediction' in results, "Missing 'new_point_prediction' in results."
    assert results['new_point_prediction'] == expected_pred, f"Expected new_point_prediction={expected_pred}, got {results['new_point_prediction']}"

    assert 'nearest_neighbor_indices' in results, "Missing 'nearest_neighbor_indices' in results."
    assert results['nearest_neighbor_indices'] == expected_neighbors, f"Expected nearest_neighbor_indices={expected_neighbors}, got {results['nearest_neighbor_indices']}"
TEST_EOF

cleanup() {
    if [ -f "$DATA_BACKUP" ]; then
        cp "$DATA_BACKUP" "$DATA"
    fi
    if [ -f "$ORIGINAL_RESULTS" ]; then
        cp "$ORIGINAL_RESULTS" "$RESULTS"
    fi
}
trap cleanup EXIT

if [ ! -f "$SRC" ] || [ ! -s "$SRC" ]; then
    echo "Missing or empty pipeline.cpp"
    score=0
fi

if [ ! -f "$DATA" ] || ! cp "$DATA" "$DATA_BACKUP"; then
    echo "Missing dataset.csv"
    score=0
fi

if [ "$score" -eq 1 ]; then
    if ! g++ -std=c++17 -O3 "$SRC" -o "$BIN"; then
        echo "pipeline.cpp did not compile"
        score=0
    elif [ ! -x "$BIN" ]; then
        echo "Compiler did not produce an executable"
        score=0
    fi
fi

run_and_check() {
    rm -f "$RESULTS"
    if ! timeout 30s "$BIN"; then
        echo "Submitted pipeline failed or timed out"
        return 1
    fi
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

# Run the submitted C++ pipeline on the provided dataset. Removing results first
# ensures a precomputed JSON file cannot satisfy the checks.
if [ "$score" -eq 1 ]; then
    if run_and_check; then
        cp "$RESULTS" "$ORIGINAL_RESULTS"
    else
        score=0
    fi
fi

# Exercise the same compiled implementation on a second dataset whose expected
# answers are independently recomputed by the existing assertions.
if [ "$score" -eq 1 ]; then
    if ! python3 - << 'PY'
import random
random.seed(7319)
with open('/home/user/data/dataset.csv', 'w') as f:
    for _ in range(100):
        x0 = random.gauss(0.4, 3.1)
        x1 = random.gauss(1.8, 1.7)
        x2 = random.gauss(-0.7, 2.4)
        x3 = random.gauss(0.2, 1.2)
        label = int(0.9*x0 + 0.65*x1 - 0.35*x2 + 0.2*x3 > 1.6)
        f.write(f'{x0:.5f},{x1:.5f},{x2:.5f},{x3:.5f},{label}\n')
PY
    then
        score=0
    elif ! run_and_check; then
        score=0
    fi
fi

cleanup
trap - EXIT
if [ "$score" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
