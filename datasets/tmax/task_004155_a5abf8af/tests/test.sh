#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import statistics
import subprocess

import pytest

SCRIPT_PATH = "/home/user/detect_anomalies.py"
CSV_PATH = "/home/user/config_metrics.csv"
OUTPUT_PATH = "/home/user/anomalies.json"


def test_anomalies_json_exists_and_correct():
    """Check that anomalies.json is generated and contains the correct data."""
    assert os.path.isfile(OUTPUT_PATH), f"File missing: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(data, list), f"Expected a JSON array in {OUTPUT_PATH}"
    assert len(data) == 1, f"Expected exactly 1 anomaly in {OUTPUT_PATH}, found {len(data)}"

    anomaly = data[0]
    assert anomaly.get("timestamp") == "2023-10-01T10:05:00", "Incorrect timestamp for the anomaly."
    assert anomaly.get("worker_threads") == 50, "Incorrect worker_threads value for the anomaly."
    assert anomaly.get("z_score") == 1.79, f"Incorrect z_score, expected 1.79, got {anomaly.get('z_score')}"


def test_crontab_configured():
    """Check that the crontab is configured correctly for the user."""
    try:
        result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        try:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
            crontab_output = result.stdout
        except subprocess.CalledProcessError:
            pytest.fail("Failed to retrieve crontab. Is it configured?")

    lines = crontab_output.strip().split('\n')
    found = False
    for line in lines:
        if line.startswith("*/5 * * * *") and "python3 /home/user/detect_anomalies.py" in line:
            found = True
            break

    assert found, "Crontab entry for detect_anomalies.py running every 5 minutes was not found."


def test_script_exists():
    """Check that the detect_anomalies.py script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"


def expected_anomalies(rows):
    expected = []
    values = [value for _, value in rows]
    for index in range(4, len(rows)):
        window = values[index - 4:index + 1]
        mean = statistics.mean(window)
        std = statistics.stdev(window)
        if std == 0:
            continue
        z_score = (values[index] - mean) / std
        if z_score > 1.5:
            expected.append({
                "timestamp": rows[index][0],
                "worker_threads": values[index],
                "z_score": round(float(z_score), 2),
            })
    return expected


def test_script_executes_and_computes_rolling_anomalies_from_changed_csv():
    """Execute the submitted script against unpredictable data and verify its calculations."""
    original_csv = open(CSV_PATH, "rb").read()
    output_existed = os.path.exists(OUTPUT_PATH)
    original_output = open(OUTPUT_PATH, "rb").read() if output_existed else None

    token = secrets.token_hex(8)
    rng = secrets.SystemRandom()
    rows = []
    for block in range(6):
        base = rng.randint(12, 70)
        block_values = [base, base + 1, base - 1, base, base + rng.randint(25, 55)]
        for offset, value in enumerate(block_values):
            index = block * 5 + offset
            rows.append((f"dynamic-{token}-{index:02d}", value))

    expected = expected_anomalies(rows)
    assert len(expected) >= 2, "Internal test data did not produce enough anomalies"

    try:
        with open(CSV_PATH, "w", newline="") as csv_file:
            writer = csv.writer(csv_file)
            writer.writerow(["timestamp", "worker_threads"])
            writer.writerows(rows)
        os.chmod(CSV_PATH, 0o666)

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "/usr/bin/env", "python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"detect_anomalies.py failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(OUTPUT_PATH), "Script did not generate /home/user/anomalies.json"

        try:
            with open(OUTPUT_PATH, "r") as output_file:
                actual = json.load(output_file)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Script generated invalid JSON: {exc}")

        assert isinstance(actual, list), "Script output must be a single JSON array"
        for item in actual:
            assert isinstance(item, dict), "Every anomaly must be a JSON object"
            assert set(item.keys()) == {"timestamp", "worker_threads", "z_score"}, (
                "Every anomaly must have exactly timestamp, worker_threads, and z_score keys"
            )
            assert isinstance(item["timestamp"], str)
            assert isinstance(item["worker_threads"], int) and not isinstance(item["worker_threads"], bool)
            assert isinstance(item["z_score"], float)
            assert math.isfinite(item["z_score"])

        assert actual == expected, f"Incorrect anomalies for changed CSV. Expected {expected}, got {actual}"
    finally:
        with open(CSV_PATH, "wb") as csv_file:
            csv_file.write(original_csv)
        if output_existed:
            with open(OUTPUT_PATH, "wb") as output_file:
                output_file.write(original_output)
        elif os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
