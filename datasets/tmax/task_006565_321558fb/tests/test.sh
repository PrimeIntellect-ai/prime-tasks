#!/bin/bash
set +e
mkdir -p /logs/verifier
export PATH="/usr/local/cargo/bin:/root/.cargo/bin:${PATH}"

WORKDIR="/tmp/etl_verifier.$$"
mkdir -p "$WORKDIR"
cp /home/user/data/input.csv "$WORKDIR/original_input.csv"

cleanup() {
    cp "$WORKDIR/original_input.csv" /home/user/data/input.csv 2>/dev/null || true
    if [ -f "$WORKDIR/original_output.csv" ]; then
        cp "$WORKDIR/original_output.csv" /home/user/data/output.csv 2>/dev/null || true
    fi
    if [ -f "$WORKDIR/original_metrics.txt" ]; then
        cp "$WORKDIR/original_metrics.txt" /home/user/metrics.txt 2>/dev/null || true
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > "$WORKDIR/test_final_state.py"
import os
import csv
import math
import pytest


def compute_expected_values(input_path):
    keywords = ["error", "fail", "timeout", "success", "connect"]
    weights = [1.2, 0.8, 0.5, -1.0, 0.3]
    bias = -0.5

    expected_outputs = {}
    probs = []

    with open(input_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            row_id = row['id']
            text = row['text'].lower()

            logit = bias
            for kw, w in zip(keywords, weights):
                count = text.count(kw)
                logit += count * w

            prob = 1.0 / (1.0 + math.exp(-logit))
            pred = 1 if prob > 0.5 else 0

            expected_outputs[row_id] = {'prob': prob, 'prediction': pred}
            probs.append(prob)

    n = len(probs)
    mean = sum(probs) / n
    variance = sum((p - mean) ** 2 for p in probs) / (n - 1)
    std_dev = math.sqrt(variance)
    stderr = std_dev / math.sqrt(n)

    lower_bound = mean - 1.96 * stderr
    upper_bound = mean + 1.96 * stderr

    return expected_outputs, mean, lower_bound, upper_bound


def test_output_csv_correctness():
    input_path = "/home/user/data/input.csv"
    output_path = "/home/user/data/output.csv"

    assert os.path.isfile(input_path), f"Input file missing at {input_path}"
    assert os.path.isfile(output_path), f"Output file missing at {output_path}"

    expected_outputs, _, _, _ = compute_expected_values(input_path)

    with open(output_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "prob", "prediction"], f"Incorrect header in output.csv: {header}"

        row_count = 0
        seen_ids = set()
        for row in reader:
            assert len(row) == 3, f"Malformed row in output.csv: {row}"
            row_id, prob_str, pred_str = row
            assert row_id in expected_outputs, f"Unexpected id {row_id} in output.csv"
            assert row_id not in seen_ids, f"Duplicate id {row_id} in output.csv"
            seen_ids.add(row_id)

            expected = expected_outputs[row_id]
            prob = float(prob_str)
            pred = int(pred_str)

            assert math.isclose(prob, expected['prob'], rel_tol=1e-4, abs_tol=1e-4), \
                f"Incorrect probability for id {row_id}: expected {expected['prob']}, got {prob}"
            assert pred == expected['prediction'], \
                f"Incorrect prediction for id {row_id}: expected {expected['prediction']}, got {pred}"

            row_count += 1

        assert row_count == len(expected_outputs), "Output CSV does not contain all expected rows."
        assert seen_ids == set(expected_outputs), "Output CSV does not contain every expected ID exactly once."


def test_metrics_txt_correctness():
    input_path = "/home/user/data/input.csv"
    metrics_path = "/home/user/metrics.txt"

    assert os.path.isfile(metrics_path), f"Metrics file missing at {metrics_path}"

    _, expected_mean, expected_lower, expected_upper = compute_expected_values(input_path)

    with open(metrics_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 3, f"Metrics file must contain exactly 3 comma-separated values, got: {content}"

    try:
        mean = float(parts[0])
        lower = float(parts[1])
        upper = float(parts[2])
    except ValueError:
        pytest.fail(f"Metrics file contains non-numeric values: {content}")

    assert math.isclose(mean, expected_mean, rel_tol=1e-3, abs_tol=1e-3), \
        f"Incorrect mean: expected {expected_mean}, got {mean}"
    assert math.isclose(lower, expected_lower, rel_tol=1e-3, abs_tol=1e-3), \
        f"Incorrect lower bound: expected {expected_lower}, got {lower}"
    assert math.isclose(upper, expected_upper, rel_tol=1e-3, abs_tol=1e-3), \
        f"Incorrect upper bound: expected {expected_upper}, got {upper}"
TEST_EOF

run_checks() {
    test -f /home/user/etl_pipeline/Cargo.toml || return 1
    test -f /home/user/etl_pipeline/src/main.rs || return 1

    # Remove hand-written/stale artifacts and force the submitted Rust project to build and run.
    rm -f /home/user/data/output.csv /home/user/metrics.txt
    cp /home/user/data/input.csv "$WORKDIR/run_input.csv" || return 1
    (
        cd /home/user/etl_pipeline || exit 1
        timeout 180s cargo clean --quiet || exit 1
        timeout 180s cargo run --quiet
    ) || return 1
    cmp -s /home/user/data/input.csv "$WORKDIR/run_input.csv" || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short || return 1

    cp /home/user/data/output.csv "$WORKDIR/original_output.csv" || return 1
    cp /home/user/metrics.txt "$WORKDIR/original_metrics.txt" || return 1

    # Exercise the compiled pipeline on an unpredictable, valid CSV input.
    python3 - "$WORKDIR/generated_input.csv" << 'GEN_EOF' || return 1
import csv
import secrets
import sys

out = sys.argv[1]
rng = secrets.SystemRandom()
keywords = ["error", "fail", "timeout", "success", "connect"]
patterns = [
    [0, 0, 0, 0, 0],
    [1, 0, 0, 0, 0],
    [0, 1, 2, 0, 0],
    [0, 0, 0, 3, 1],
    [2, 1, 1, 0, 2],
]
while len(patterns) < 13:
    patterns.append([rng.randrange(0, 4) for _ in keywords])
rng.shuffle(patterns)

with open(out, 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'text'])
    for counts in patterns:
        row_id = secrets.token_hex(6)
        words = ['ordinary', 'message']
        for kw, count in zip(keywords, counts):
            for _ in range(count):
                style = rng.randrange(3)
                words.append(kw.upper() if style == 0 else kw.title() if style == 1 else kw)
        rng.shuffle(words)
        writer.writerow([row_id, ', '.join(words)])
GEN_EOF

    cp "$WORKDIR/generated_input.csv" /home/user/data/input.csv || return 1
    cp /home/user/data/input.csv "$WORKDIR/generated_snapshot.csv" || return 1
    rm -f /home/user/data/output.csv /home/user/metrics.txt
    (
        cd /home/user/etl_pipeline || exit 1
        timeout 180s cargo run --quiet
    ) || return 1
    cmp -s /home/user/data/input.csv "$WORKDIR/generated_snapshot.csv" || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short || return 1

    return 0
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
