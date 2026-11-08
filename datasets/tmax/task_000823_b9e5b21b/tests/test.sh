#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import secrets
import subprocess
import pytest

GO_SOURCE = "/home/user/audit.go"
CSV_PATH = "/home/user/etl_dump.csv"
JSON_PATH = "/home/user/audit_results.json"
BINARY_PATH = "/tmp/audit_submission"

with open(CSV_PATH, "rb") as f:
    ORIGINAL_CSV = f.read()
ORIGINAL_RESULT = None


def run_audit():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(JSON_PATH), "Executing audit.go did not create /home/user/audit_results.json"


def expected_metrics(csv_path):
    total_rows = 0
    corrupt_rows = 0
    x = []
    y = []

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            rec_id = float(row[0])
            val = row[1]
            is_corrupt = 1.0 if ('.' in val or val == 'NaN') else 0.0
            x.append(rec_id)
            y.append(is_corrupt)
            total_rows += 1
            if is_corrupt == 1.0:
                corrupt_rows += 1

    mean_x = sum(x) / total_rows
    mean_y = sum(y) / total_rows
    cov = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y)) / (total_rows - 1)
    posterior = (1.0 + corrupt_rows) / (2.0 + total_rows)
    return total_rows, corrupt_rows, posterior, cov


def assert_results_correct(csv_path):
    with open(JSON_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("audit_results.json is not a valid JSON file.")

    total_rows, corrupt_rows, expected_posterior_mean, cov = expected_metrics(csv_path)

    assert "total_rows" in results, "Missing 'total_rows' in JSON output."
    assert "corrupt_rows" in results, "Missing 'corrupt_rows' in JSON output."
    assert "posterior_mean" in results, "Missing 'posterior_mean' in JSON output."
    assert "covariance" in results, "Missing 'covariance' in JSON output."

    assert results["total_rows"] == total_rows, f"Expected total_rows to be {total_rows}, got {results['total_rows']}"
    assert results["corrupt_rows"] == corrupt_rows, f"Expected corrupt_rows to be {corrupt_rows}, got {results['corrupt_rows']}"
    assert math.isclose(results["posterior_mean"], expected_posterior_mean, rel_tol=1e-5), f"Expected posterior_mean to be close to {expected_posterior_mean}, got {results['posterior_mean']}"
    assert math.isclose(results["covariance"], cov, rel_tol=1e-5), f"Expected covariance to be close to {cov}, got {results['covariance']}"


def test_audit_go_exists():
    """Test that the Go source code file exists."""
    assert os.path.isfile(GO_SOURCE), "The file /home/user/audit.go does not exist."


def test_go_program_compiles_and_executes():
    """Compile the submitted Go source and execute it on the supplied dump."""
    global ORIGINAL_RESULT
    with open(CSV_PATH, "wb") as f:
        f.write(ORIGINAL_CSV)
    subprocess.run(
        ["go", "build", "-o", BINARY_PATH, GO_SOURCE],
        cwd="/home/user",
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    run_audit()
    with open(JSON_PATH, "rb") as f:
        ORIGINAL_RESULT = f.read()


def test_audit_results_exist():
    """Test that the audit_results.json file exists."""
    assert os.path.isfile(JSON_PATH), "The file /home/user/audit_results.json does not exist."


def test_audit_results_correctness():
    """Test that the values in audit_results.json are correct based on the data."""
    assert os.path.isfile(JSON_PATH), "Missing audit_results.json"
    assert os.path.isfile(CSV_PATH), "Missing etl_dump.csv"
    assert_results_correct(CSV_PATH)


def test_go_program_handles_derived_input():
    """Execute the compiled submission on an unpredictable valid CSV dump."""
    rng = secrets.SystemRandom()
    record_ids = rng.sample(range(10000, 900000), 91)
    rows = []
    for i, record_id in enumerate(record_ids):
        if i % 6 == 0:
            value = "NaN"
        elif i % 7 == 0:
            value = f"{rng.randrange(-500, 500)}.0"
        else:
            value = str(rng.randrange(-100000, 100000))
        rows.append((record_id, value))

    try:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["record_id", "value"])
            writer.writerows(rows)
        run_audit()
        assert_results_correct(CSV_PATH)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(ORIGINAL_CSV)
        if ORIGINAL_RESULT is not None:
            with open(JSON_PATH, "wb") as f:
                f.write(ORIGINAL_RESULT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
