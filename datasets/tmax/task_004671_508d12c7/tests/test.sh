#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_build_model_script_exists_and_executable():
    script_path = "/home/user/build_model.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

def test_benchmark_script_exists_and_executable():
    script_path = "/home/user/benchmark.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

def test_model_tsv_content():
    model_path = "/home/user/model.tsv"
    assert os.path.isfile(model_path), f"Missing file: {model_path}"

    expected_lines = [
        "brown\tdog\t0.2500",
        "brown\tfox\t0.2500",
        "fast\tbrown\t0.2857",
        "quick\tbrown\t0.2857",
        "the\tfast\t0.2500",
        "the\tquick\t0.2500"
    ]

    with open(model_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Content of {model_path} does not match expected output."

def test_scores_tsv_content():
    scores_path = "/home/user/scores.tsv"
    assert os.path.isfile(scores_path), f"Missing file: {scores_path}"

    expected_scores = {
        1: -4.0253,
        2: -3.7377
    }

    with open(scores_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected 2 lines in {scores_path}, found {len(lines)}"

    for line in lines:
        parts = line.split('\t')
        assert len(parts) == 2, f"Invalid line format in {scores_path}: {line}"
        line_num = int(parts[0])
        score = float(parts[1])

        assert line_num in expected_scores, f"Unexpected line number: {line_num}"
        expected_score = expected_scores[line_num]

        assert abs(score - expected_score) <= 0.0015, f"Score for line {line_num} is {score}, expected {expected_score} (+/- 0.001)"

def test_time_log_exists_and_not_empty():
    log_path = "/home/user/time.log"
    assert os.path.isfile(log_path), f"Missing file: {log_path}"
    assert os.path.getsize(log_path) > 0, f"File {log_path} is empty"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
