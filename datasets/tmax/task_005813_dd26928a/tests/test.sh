#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import stat

VOCAB = {
    '+': 0, '-': 1, '*': 2, '/': 3, '(': 4, ')': 5,
    '0': 6, '1': 7, '2': 8, '3': 9, '4': 10, '5': 11,
    '6': 12, '7': 13, '8': 14, '9': 15, '.': 16
}

def compute_expected_data(raw_path):
    expected_processed = []
    mse_sum = 0.0
    count = 0

    with open(raw_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            expr = obj['expr']

            # Evaluate true value
            # Remove spaces for eval if needed, but python eval handles spaces fine
            true_value = float(eval(expr))

            tokens = expr.split(' ')
            token_ids = [VOCAB[t] for t in tokens]

            expected_processed.append({
                "id": obj["id"],
                "tokens": tokens,
                "token_ids": token_ids,
                "true_value": true_value
            })

            # Predict
            pred = sum((0.15 * tid) for tid in token_ids) + 1.5
            mse_sum += (pred - true_value) ** 2
            count += 1

    expected_mse = mse_sum / count if count > 0 else 0.0
    return expected_processed, expected_mse

def test_run_pipeline_exists_and_executable():
    """Test that the bash script exists and is executable."""
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), f"Missing pipeline script: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

def test_processed_dataset():
    """Test that the processed dataset is correct according to the schema and calculations."""
    raw_path = "/home/user/raw_math.jsonl"
    processed_path = "/home/user/processed_dataset.jsonl"

    assert os.path.exists(processed_path), f"Missing processed dataset: {processed_path}"

    expected_processed, _ = compute_expected_data(raw_path)

    actual_processed = []
    with open(processed_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                actual_processed.append(obj)
            except json.JSONDecodeError:
                assert False, f"Invalid JSON on line {line_num} in {processed_path}"

    assert len(actual_processed) == len(expected_processed), \
        f"Expected {len(expected_processed)} lines in {processed_path}, got {len(actual_processed)}"

    for i, (actual, expected) in enumerate(zip(actual_processed, expected_processed)):
        assert "id" in actual, f"Missing 'id' in processed data line {i+1}"
        assert "tokens" in actual, f"Missing 'tokens' in processed data line {i+1}"
        assert "token_ids" in actual, f"Missing 'token_ids' in processed data line {i+1}"
        assert "true_value" in actual, f"Missing 'true_value' in processed data line {i+1}"

        assert actual["id"] == expected["id"], f"ID mismatch on line {i+1}"
        assert actual["tokens"] == expected["tokens"], f"Tokens mismatch on line {i+1}"
        assert actual["token_ids"] == expected["token_ids"], f"Token IDs mismatch on line {i+1}"
        assert math.isclose(actual["true_value"], expected["true_value"], rel_tol=1e-5), \
            f"True value mismatch on line {i+1}: expected {expected['true_value']}, got {actual['true_value']}"

def test_metrics_json():
    """Test that the metrics file contains the correct MSE."""
    raw_path = "/home/user/raw_math.jsonl"
    metrics_path = "/home/user/metrics.json"

    assert os.path.exists(metrics_path), f"Missing metrics file: {metrics_path}"

    _, expected_mse = compute_expected_data(raw_path)

    with open(metrics_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Invalid JSON in {metrics_path}"

    assert "mse" in data, f"Missing 'mse' key in {metrics_path}"
    actual_mse = data["mse"]

    assert isinstance(actual_mse, float) or isinstance(actual_mse, int), f"'mse' must be a number, got {type(actual_mse)}"
    assert math.isclose(actual_mse, expected_mse, rel_tol=1e-4), \
        f"MSE mismatch: expected {expected_mse}, got {actual_mse}"
TEST_EOF

reward=0
challenge_status=1
original_status=1
backup=/tmp/raw_math.original.jsonl

if cp /home/user/raw_math.jsonl "$backup" && python3 - << 'PY_EOF'
import json
import secrets

rows = []
for index in range(7):
    a = secrets.randbelow(10)
    b = secrets.randbelow(10)
    c = secrets.randbelow(9) + 1
    forms = [
        f"{a} + {b} * {c}",
        f"( {a} + {b} ) * {c}",
        f"{a} * {b} - {c}",
        f"( {a} + {b} ) / {c}",
    ]
    rows.append({"id": secrets.randbelow(900000) + 100000, "expr": forms[index % len(forms)]})

with open('/home/user/raw_math.jsonl', 'w') as f:
    for row in rows:
        f.write(json.dumps(row) + '\n')
PY_EOF
then
    rm -f /home/user/processed_dataset.jsonl /home/user/metrics.json
    if (cd /home/user && timeout 30s /home/user/run_pipeline.sh); then
        if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
            challenge_status=0
        fi
    fi
fi

if [ -f "$backup" ]; then
    cp "$backup" /home/user/raw_math.jsonl
    rm -f /home/user/processed_dataset.jsonl /home/user/metrics.json
    if (cd /home/user && timeout 30s /home/user/run_pipeline.sh); then
        if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
            original_status=0
        fi
    fi
fi

if [ "$challenge_status" -eq 0 ] && [ "$original_status" -eq 0 ]; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
