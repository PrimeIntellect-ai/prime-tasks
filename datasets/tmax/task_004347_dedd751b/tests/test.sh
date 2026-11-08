#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

BACKUP_DIR=$(mktemp -d) || exit 0
BIN_PATH=$(mktemp /tmp/analyze_verifier.XXXXXX) || exit 0
VALID_REPORT="$BACKUP_DIR/report.csv"

cleanup() {
    if [ -f "$BACKUP_DIR/configs.csv" ]; then cp "$BACKUP_DIR/configs.csv" /home/user/configs.csv 2>/dev/null || true; fi
    if [ -f "$BACKUP_DIR/metrics.csv" ]; then cp "$BACKUP_DIR/metrics.csv" /home/user/metrics.csv 2>/dev/null || true; fi
    if [ -f "$BACKUP_DIR/weights.txt" ]; then cp "$BACKUP_DIR/weights.txt" /home/user/weights.txt 2>/dev/null || true; fi
    if [ -f "$VALID_REPORT" ]; then cp "$VALID_REPORT" /home/user/report.csv 2>/dev/null || true; fi
    rm -f "$BIN_PATH"
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
from collections import defaultdict

def test_report_csv_correctness():
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"Output file {report_path} is missing. Did you run your C++ program?"

    configs_path = "/home/user/configs.csv"
    metrics_path = "/home/user/metrics.csv"
    weights_path = "/home/user/weights.txt"

    assert os.path.isfile(configs_path), f"{configs_path} is missing."
    assert os.path.isfile(metrics_path), f"{metrics_path} is missing."
    assert os.path.isfile(weights_path), f"{weights_path} is missing."

    # Read weights
    with open(weights_path, "r") as f:
        weights = [float(line.strip()) for line in f if line.strip()]

    # Read configs
    run_to_model = {}
    with open(configs_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            run_to_model[row['run_id']] = row['model_type']

    # Read metrics and compute scores
    model_scores = defaultdict(list)
    with open(metrics_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            run_id = row['run_id']
            metrics = [
                float(row['m1']),
                float(row['m2']),
                float(row['m3']),
                float(row['m4']),
                float(row['m5'])
            ]
            score = sum(m * w for m, w in zip(metrics, weights))
            model_type = run_to_model[run_id]
            model_scores[model_type].append(score)

    # Compute means and sort
    model_means = []
    for model_type, scores in model_scores.items():
        mean_score = sum(scores) / len(scores)
        model_means.append((model_type, mean_score))

    model_means.sort(key=lambda x: x[1], reverse=True)

    # Format expected output
    expected_lines = [f"{model_type},{mean_score:.4f}" for model_type, mean_score in model_means]

    # Read actual output
    with open(report_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in report.csv, got {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"
TEST_EOF

run_verification() {
    [ -f /home/user/analyze.cpp ] || return 1
    [ -f /home/user/configs.csv ] || return 1
    [ -f /home/user/metrics.csv ] || return 1
    [ -f /home/user/weights.txt ] || return 1

    cp /home/user/configs.csv "$BACKUP_DIR/configs.csv" || return 1
    cp /home/user/metrics.csv "$BACKUP_DIR/metrics.csv" || return 1
    cp /home/user/weights.txt "$BACKUP_DIR/weights.txt" || return 1

    g++ -std=c++17 -O2 /home/user/analyze.cpp -o "$BIN_PATH" || return 1
    [ -x "$BIN_PATH" ] || return 1

    sha256sum /home/user/configs.csv /home/user/metrics.csv /home/user/weights.txt > "$BACKUP_DIR/original.hash" || return 1
    rm -f /home/user/report.csv
    (cd /home/user && timeout 15s "$BIN_PATH") || return 1
    sha256sum /home/user/configs.csv /home/user/metrics.csv /home/user/weights.txt | cmp -s - "$BACKUP_DIR/original.hash" || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
    cp /home/user/report.csv "$VALID_REPORT" || return 1

    python3 - << 'PY_EOF' || return 1
import csv
import secrets

while True:
    token = secrets.token_hex(4)
    families = [f"Family_{token}_{i}" for i in range(3)]
    run_ids = [f"case_{token}_{i}" for i in range(6)]
    weights = []
    while len(weights) < 5:
        value = secrets.randbelow(11) - 5
        if value != 0:
            weights.append(value)
    metrics = [[secrets.randbelow(30) + 1 for _ in range(5)] for _ in range(6)]
    scores = [sum(a * b for a, b in zip(row, weights)) for row in metrics]
    means = [(scores[2*i] + scores[2*i+1]) / 2 for i in range(3)]
    if len(set(means)) == 3:
        break

with open('/home/user/configs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['run_id', 'model_type'])
    for i, run_id in enumerate(run_ids):
        writer.writerow([run_id, families[i // 2]])

with open('/home/user/metrics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['run_id', 'm1', 'm2', 'm3', 'm4', 'm5'])
    # Deliberately use a different row order so the implementation must join by run_id.
    for i in [5, 2, 0, 4, 1, 3]:
        writer.writerow([run_ids[i], *metrics[i]])

with open('/home/user/weights.txt', 'w') as f:
    for weight in weights:
        f.write(f'{weight}\n')
PY_EOF

    sha256sum /home/user/configs.csv /home/user/metrics.csv /home/user/weights.txt > "$BACKUP_DIR/dynamic.hash" || return 1
    rm -f /home/user/report.csv
    (cd /home/user && timeout 15s "$BIN_PATH") || return 1
    sha256sum /home/user/configs.csv /home/user/metrics.csv /home/user/weights.txt | cmp -s - "$BACKUP_DIR/dynamic.hash" || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
