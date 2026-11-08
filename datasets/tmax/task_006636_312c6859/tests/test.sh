#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import stat
import subprocess
from pathlib import Path

import pytest

ANALYSIS_DIR = Path("/home/user/abstract_analysis")
ANALYZE_GO = ANALYSIS_DIR / "analyze.go"
GO_MOD = ANALYSIS_DIR / "go.mod"
DATASET = Path("/home/user/dataset.csv")
RESULTS = Path("/home/user/results.json")


def assert_regular_file(path):
    try:
        mode = os.lstat(path).st_mode
    except FileNotFoundError:
        pytest.fail(f"Required file not found at: {path}")
    assert stat.S_ISREG(mode), f"Required path is not a regular file: {path}"


def run_program():
    if RESULTS.exists() or RESULTS.is_symlink():
        RESULTS.unlink()
    completed = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "go", "run", "analyze.go"],
        cwd=str(ANALYSIS_DIR),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert completed.returncode == 0, (
        f"Go program failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert RESULTS.is_file(), "Go program did not create /home/user/results.json"


def write_dataset(rows):
    with DATASET.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "abstract", "citations"])
        writer.writerows(rows)


def expected_for(rows):
    vectors = []
    citations = []
    for _, abstract, citation in rows:
        vector = [0.0] * 128
        for character in abstract:
            value = ord(character)
            if 0 <= value <= 127:
                vector[value] += 1.0
        norm = math.sqrt(sum(value * value for value in vector))
        if norm != 0.0:
            vector = [value / norm for value in vector]
        vectors.append(vector)
        citations.append(int(citation))

    similarities = []
    differences = []
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            similarities.append(sum(a * b for a, b in zip(vectors[i], vectors[j])))
            differences.append(float(abs(citations[i] - citations[j])))

    mean_x = sum(similarities) / len(similarities)
    mean_y = sum(differences) / len(differences)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(similarities, differences))
    denominator = math.sqrt(
        sum((x - mean_x) ** 2 for x in similarities)
        * sum((y - mean_y) ** 2 for y in differences)
    )
    correlation = numerator / denominator
    pair_count = len(similarities)
    z = 0.5 * math.log((1.0 + correlation) / (1.0 - correlation))
    se = 1.0 / math.sqrt(pair_count - 3)

    def inverse_fisher(value):
        exp_value = math.exp(2.0 * value)
        return (exp_value - 1.0) / (exp_value + 1.0)

    return {
        "correlation": round(correlation, 4),
        "ci_lower": round(inverse_fisher(z - 1.96 * se), 4),
        "ci_upper": round(inverse_fisher(z + 1.96 * se), 4),
    }


def assert_dynamic_result(expected):
    with RESULTS.open("r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} does not contain valid JSON.")
    expected_keys = {"correlation", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected. Found: {list(data.keys())}"
    for key, expected_value in expected.items():
        actual = data[key]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"Value for '{key}' must be a number."
        assert math.isfinite(actual), f"Value for '{key}' must be finite."
        assert abs(actual - expected_value) <= 0.00011, (
            f"Value for '{key}' is {actual}, expected rounded value {expected_value}"
        )


def test_go_artifacts_exist():
    assert ANALYSIS_DIR.is_dir(), f"Go module directory not found at: {ANALYSIS_DIR}"
    assert_regular_file(ANALYZE_GO)
    assert_regular_file(GO_MOD)


def test_program_computes_results_for_changed_inputs():
    original_dataset = DATASET.read_bytes()
    cases = [
        [
            ("a1", "Aa aa!!", 3),
            ("a2", "BBBB cc", 41),
            ("a3", "", 9),
            ("a4", "123 data", 87),
            ("a5", "Symbols []{}", 22),
            ("a6", "naïve café", 150),
            ("a7", "Z z z", 11),
        ],
        [
            ("b1", "alpha", 2),
            ("b2", "ALPHA", 70),
            ("b3", "beta beta", 17),
            ("b4", "gamma!", 101),
            ("b5", "\t tabs", 33),
            ("b6", "xyz 123", 8),
        ],
    ]
    try:
        for rows in cases:
            write_dataset(rows)
            run_program()
            assert_dynamic_result(expected_for(rows))
    finally:
        DATASET.write_bytes(original_dataset)
        run_program()


def test_results_json_exists():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Output file not found at: {results_path}"


def test_results_json_content():
    results_path = "/home/user/results.json"
    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    expected_keys = {"correlation", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected. Found: {list(data.keys())}"

    expected_values = {
        "correlation": 0.0409,
        "ci_lower": -0.3421,
        "ci_upper": 0.4137
    }

    tolerance = 0.0002

    for key, expected_val in expected_values.items():
        actual_val = data[key]
        assert isinstance(actual_val, (int, float)), f"Value for '{key}' must be a number."
        assert abs(actual_val - expected_val) <= tolerance, \
            f"Value for '{key}' is {actual_val}, expected {expected_val} (tolerance {tolerance})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
