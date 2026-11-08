#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import requests
import pytest


def canonical_data():
    rng = random.Random(42)
    rows = []
    for i in range(1, 1001):
        if rng.random() < 0.1:
            val = -999.0
        else:
            val = rng.gauss(50.0, 5.0)
            if i > 800 and rng.random() < 0.05:
                val = 100.0
        rows.append(f"{i},{val:.2f}\n")
    return "".join(rows)


def test_final_state():
    data_path = "/home/user/data.csv"
    assert os.path.isfile(data_path), f"Missing original data file: {data_path}"

    with open(data_path, "r") as f:
        actual_data = f.read()

    # The expected result must be based on the immutable fixture created by setup,
    # not on an agent-modified replacement data.csv.
    assert actual_data == canonical_data(), f"Original data fixture was modified: {data_path}"

    lines = [line.strip() for line in actual_data.splitlines() if line.strip()]
    assert len(lines) == 1000, f"Expected 1000 rows in {data_path}, found {len(lines)}"

    # Compute the training mean (first 800 rows)
    train_sum = 0.0
    train_count = 0
    for line in lines[:800]:
        parts = line.split(",")
        val = float(parts[1])
        if val != -999.0:
            train_sum += val
            train_count += 1

    train_mean = train_sum / train_count if train_count > 0 else 0.0

    # Compute the expected final test set
    expected_lines = []
    for line in lines[800:]:
        parts = line.split(",")
        id_str = parts[0]
        val = float(parts[1])

        if val == -999.0:
            val = train_mean

        # The C code uses %.2f for output
        val_formatted = f"{val:.2f}"
        val_parsed = float(val_formatted)

        # Outlier scorer logic: score = fabs(val - 50.0) / 20.0
        score = abs(val_parsed - 50.0) / 20.0

        if score <= 0.80:
            expected_lines.append(f"{id_str},{val_formatted}")

    # Fetch from the HTTP server
    url = "http://127.0.0.1:8080/final_test.csv"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text[:200]}"

    actual_content = response.text

    # Compare actual vs expected
    actual_lines = [line.strip() for line in actual_content.strip().split("\n") if line.strip()]

    assert actual_lines == expected_lines, "The downloaded final_test.csv does not match the expected output. Either the mean was computed incorrectly, the imputation failed, or the outlier filtering was incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
