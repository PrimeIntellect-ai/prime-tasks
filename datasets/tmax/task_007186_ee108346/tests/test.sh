#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
SOURCE = "/home/user/analyze.go"
RESULTS = "/home/user/results.json"
BINARY = "/tmp/analyze_submission"


def run_program():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    subprocess.run([BINARY], cwd=HOME, check=True, timeout=20)
    assert os.path.isfile(RESULTS), "Running analyze.go did not generate /home/user/results.json."


def load_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} does not contain valid JSON.")


def assert_values(results, expected):
    assert "A" in results, "Missing variant 'A' in results."
    assert "B" in results, "Missing variant 'B' in results."
    for variant in ("A", "B"):
        for key, expected_val in expected[variant].items():
            assert key in results[variant], f"Missing key '{key}' in variant '{variant}'."
            actual_val = results[variant][key]
            assert isinstance(actual_val, (int, float)), f"Value for '{key}' in variant '{variant}' must be a number."
            assert math.isfinite(actual_val), f"Value for '{key}' in variant '{variant}' must be finite."
            assert abs(actual_val - expected_val) <= 0.0001, \
                f"Expected {key} for {variant} to be close to {expected_val}, got {actual_val}."


def posterior(n, k):
    alpha = 1 + k
    beta = 1 + n - k
    mean = alpha / (alpha + beta)
    variance = alpha * beta / ((alpha + beta) ** 2 * (alpha + beta + 1))
    sigma = math.sqrt(variance)
    return {
        "mean": round(mean, 4),
        "variance": round(variance, 4),
        "ci_lower": round(mean - 1.96 * sigma, 4),
        "ci_upper": round(mean + 1.96 * sigma, 4),
    }


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.exists(SOURCE), f"File {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"File {SOURCE} is not a regular file."
    subprocess.run(["go", "build", "-o", BINARY, SOURCE], cwd=HOME, check=True, timeout=30)
    run_program()


def test_analyze_go_exists():
    file_path = "/home/user/analyze.go"
    assert os.path.exists(file_path), f"File {file_path} is missing."


def test_results_json_exists_and_correct():
    file_path = "/home/user/results.json"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    results = load_results()

    expected_A = {
        "mean": 0.1208,
        "variance": 0.0001,
        "ci_lower": 0.1006,
        "ci_upper": 0.1409
    }

    expected_B = {
        "mean": 0.1530,
        "variance": 0.0001,
        "ci_lower": 0.1313,
        "ci_upper": 0.1748
    }

    assert_values(results, {"A": expected_A, "B": expected_B})


def test_program_recomputes_results_from_changed_data():
    # Generate values unavailable when the submission was written.
    a1_n = 310 + secrets.randbelow(90)
    a1_k = 25 + secrets.randbelow(20)
    a2_n = 420 + secrets.randbelow(90)
    a2_k = 45 + secrets.randbelow(20)
    b1_n = 360 + secrets.randbelow(90)
    b1_k = 65 + secrets.randbelow(20)
    b2_n = 470 + secrets.randbelow(90)
    b2_k = 85 + secrets.randbelow(20)

    valid_rows = [
        ["2024-01-01", "A", a1_n, a1_k],
        ["2024-01-02", "A", a2_n, a2_k],
        ["2024-01-01", "B", b1_n, b1_k],
        ["2024-01-02", "B", b2_n, b2_k],
    ]
    raw_rows = valid_rows + [
        ["2024-01-03", "A", -9000, 0],
        ["2024-01-03", "B", 9000, -7],
        ["2024-01-04", "A", 0, 0],
    ]

    csv_paths = []
    for root, _, files in os.walk(HOME):
        for name in files:
            if name.lower().endswith(".csv"):
                csv_paths.append(os.path.join(root, name))
    campaign = "/home/user/campaign_data.csv"
    assert campaign in csv_paths, f"File {campaign} is missing."

    non_campaign = [p for p in csv_paths if p != campaign]
    campaign_had_invalid = False
    try:
        with open(campaign, newline="") as f:
            for row in csv.DictReader(f):
                if int(row["visitors"]) <= 0 or int(row["conversions"]) < 0:
                    campaign_had_invalid = True
                    break
    except Exception:
        pass

    for path in csv_paths:
        try:
            with open(path, "r") as f:
                first_line = f.readline().strip().lower()
        except Exception:
            first_line = ""
        had_header = first_line.startswith("date,")

        # A separate cleaned CSV receives only valid rows. If there is no
        # separate cleaned artifact, exercise filtering through campaign_data.
        rows = valid_rows
        if path == campaign and (non_campaign or campaign_had_invalid):
            rows = raw_rows

        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            if had_header or path == campaign:
                writer.writerow(["date", "variant", "visitors", "conversions"])
            writer.writerows(rows)

    expected = {
        "A": posterior(a1_n + a2_n, a1_k + a2_k),
        "B": posterior(b1_n + b2_n, b1_k + b2_k),
    }
    run_program()
    assert_values(load_results(), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
