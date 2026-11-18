#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

TOKENIZED_FILE = "/home/user/data/processed/tokenized.jsonl"
METRICS_FILE = "/home/user/metrics/run_log.json"

def test_files_exist():
    assert os.path.exists(TOKENIZED_FILE), f"Tokenized file missing: {TOKENIZED_FILE}"
    assert os.path.exists(METRICS_FILE), f"Metrics file missing: {METRICS_FILE}"

def test_metrics_content():
    with open(METRICS_FILE, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Metrics file {METRICS_FILE} is not valid JSON.")

    assert "total_lines" in metrics, "Missing 'total_lines' in metrics."
    assert "valid_lines" in metrics, "Missing 'valid_lines' in metrics."
    assert "vocab_size" in metrics, "Missing 'vocab_size' in metrics."

    assert metrics["total_lines"] == 6, f"Expected total_lines to be 6, got {metrics['total_lines']}"
    assert metrics["valid_lines"] == 4, f"Expected valid_lines to be 4, got {metrics['valid_lines']}"
    assert metrics["vocab_size"] == 16, f"Expected vocab_size to be 16, got {metrics['vocab_size']}"

def test_tokenized_content():
    expected_lines = [
        {"tokens": ["2", "x", "+", "3.1", "=", "7"]},
        {"tokens": ["y", "=", "m", "*", "x", "+", "c"]},
        {"tokens": ["func", "(", "x", ")", "=", "x", "*", "2"]},
        {"tokens": ["10.5", "/", "2", "=", "5.25"]}
    ]

    with open(TOKENIZED_FILE, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 4, f"Expected 4 lines in JSONL output, got {len(lines)}"

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {TOKENIZED_FILE} is not valid JSON.")

        assert "tokens" in data, f"Missing 'tokens' key in line {i+1}"
        assert data == expected_lines[i], f"Mismatch in line {i+1}. Expected {expected_lines[i]}, got {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
