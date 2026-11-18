#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import json
import csv
import math
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/analyze_drift.py"
LOG_PATH = "/home/user/pipeline.log"
JSON_PATH = "/home/user/drift_summary.json"
ALPHA_PATH = "/home/user/data/server_alpha.csv"
BETA_PATH = "/home/user/data/server_beta.csv"

@pytest.fixture(scope="module", autouse=True)
def execute_script_on_fresh_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    rng = secrets.SystemRandom()
    header = "date,cache_size,timeout,max_workers\n"
    alpha_dates = ["2041-07-01", "2041-07-02", "2041-07-03", "2041-07-04"]
    beta_dates = ["2041-07-04", "2041-07-02", "2041-07-05", "2041-07-01"]

    def make_rows(dates):
        rows = []
        for date in dates:
            rows.append(
                f"{date},{rng.randrange(80, 401)},{rng.randrange(10, 121)},{rng.randrange(2, 65)}\n"
            )
        return rows

    alpha_bytes = (header + "".join(make_rows(alpha_dates))).encode("utf-8")
    beta_bytes = (header + "".join(make_rows(beta_dates))).encode("utf-16le")

    with open(ALPHA_PATH, "wb") as f:
        f.write(alpha_bytes)
    with open(BETA_PATH, "wb") as f:
        f.write(beta_bytes)

    for path in (LOG_PATH, JSON_PATH):
        if os.path.lexists(path):
            os.remove(path)

    try:
        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"The script {SCRIPT_PATH} did not complete within 20 seconds.")

    assert completed.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    with open(ALPHA_PATH, "rb") as f:
        assert f.read() == alpha_bytes, "The script modified server_alpha.csv."
    with open(BETA_PATH, "rb") as f:
        assert f.read() == beta_bytes, "The script modified server_beta.csv."

    yield

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

def test_json_output_correctness():
    assert os.path.isfile(JSON_PATH), f"The output JSON {JSON_PATH} is missing."

    # Recompute expected values from the actual data files
    alpha_data = {}
    with open(ALPHA_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            alpha_data[row['date']] = (int(row['cache_size']), int(row['timeout']), int(row['max_workers']))

    beta_data = {}
    with open(BETA_PATH, 'r', encoding='utf-16le') as f:
        reader = csv.DictReader(f)
        for row in reader:
            beta_data[row['date']] = (int(row['cache_size']), int(row['timeout']), int(row['max_workers']))

    common_dates = set(alpha_data.keys()).intersection(set(beta_data.keys()))
    assert len(common_dates) > 0, "No common dates found between the two servers."

    distances = []
    for date in common_dates:
        a = alpha_data[date]
        b = beta_data[date]
        dist = math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2)
        distances.append(dist)

    expected_min = round(min(distances), 4)
    expected_max = round(max(distances), 4)
    expected_mean = round(sum(distances) / len(distances), 4)

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} is not a valid JSON.")

    assert "min_drift" in result, "Key 'min_drift' is missing from the JSON output."
    assert "max_drift" in result, "Key 'max_drift' is missing from the JSON output."
    assert "mean_drift" in result, "Key 'mean_drift' is missing from the JSON output."

    assert isinstance(result["min_drift"], float), "'min_drift' must be a float."
    assert isinstance(result["max_drift"], float), "'max_drift' must be a float."
    assert isinstance(result["mean_drift"], float), "'mean_drift' must be a float."

    assert result["min_drift"] == expected_min, f"Expected min_drift {expected_min}, got {result['min_drift']}"
    assert result["max_drift"] == expected_max, f"Expected max_drift {expected_max}, got {result['max_drift']}"
    assert result["mean_drift"] == expected_mean, f"Expected mean_drift {expected_mean}, got {result['mean_drift']}"

def test_pipeline_log():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} is missing."

    with open(LOG_PATH, 'r', encoding='utf-8') as f:
        log_lines = [line.strip() for line in f if line.strip()]

    assert len(log_lines) > 0, "The log file is empty."

    required_messages = [
        "Pipeline STARTED",
        "Successfully parsed input files",
        "Pipeline COMPLETED"
    ]

    found_messages = set()

    # The expected format is %(asctime)s - %(levelname)s - %(message)s
    # Example: 2023-10-25 12:34:56,789 - INFO - Pipeline STARTED
    log_pattern = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:,\d{3})? - (INFO|WARNING|ERROR|DEBUG|CRITICAL) - (.*)$")

    for line in log_lines:
        match = log_pattern.match(line)
        assert match, f"Log line does not match the required format '%(asctime)s - %(levelname)s - %(message)s': {line}"

        level, message = match.groups()
        if message in required_messages:
            assert level == "INFO", f"Message '{message}' should be logged at INFO level, found {level}."
            found_messages.add(message)

    for req in required_messages:
        assert req in found_messages, f"Required log message '{req}' was not found in the log file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
