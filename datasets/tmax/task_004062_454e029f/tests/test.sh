#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from collections import defaultdict

import pytest

SCRIPT_PATH = "/home/user/process.sh"
RAW_PATH = "/home/user/raw_sensors.csv"
OUTPUT_PATH = "/home/user/processed_hourly.csv"


def expected_output(raw_text):
    lines = raw_text.splitlines()

    # Preserve the original verifier's interpretation: retain physical lines
    # with exactly three commas, then explicitly exclude the supplied header.
    valid_lines = [line for line in lines if line.count(",") == 3]
    if valid_lines and valid_lines[0].startswith("timestamp"):
        valid_lines = valid_lines[1:]

    records = []
    last_temp = None
    for line in valid_lines:
        parts = line.split(",")
        timestamp = parts[0]
        temp_str = parts[2]

        if temp_str.strip() == "":
            temp = last_temp
        else:
            temp = float(temp_str)
            last_temp = temp

        records.append((timestamp[:13], temp))

    hourly_temps = defaultdict(list)
    for hour, temp in records:
        hourly_temps[hour].append(temp)

    hourly_means = {
        hour: sum(temps) / len(temps)
        for hour, temps in hourly_temps.items()
    }

    if not hourly_means:
        return []

    min_mean = min(hourly_means.values())
    max_mean = max(hourly_means.values())
    result = []
    for hour in sorted(hourly_means):
        mean = hourly_means[hour]
        norm = 0.0 if max_mean == min_mean else (mean - min_mean) / (max_mean - min_mean)
        result.append(f"{hour},{mean:.4f},{norm:.4f}")
    return result


def run_pipeline(raw_text):
    with open(RAW_PATH, "w") as f:
        f.write(raw_text)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not generated."

    with open(OUTPUT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    expected_lines = expected_output(raw_text)
    assert actual_lines == expected_lines, (
        f"Content of {OUTPUT_PATH} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
    return actual_lines


def test_process_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_processed_hourly_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not generated."


def test_processed_hourly_content():
    assert os.path.isfile(RAW_PATH), f"Raw file {RAW_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(RAW_PATH, "r") as f:
        original_raw = f.read()

    original_output = None
    try:
        # Execute the submitted artifact on the supplied data rather than
        # trusting an output file created before verification.
        original_output = run_pipeline(original_raw)

        # Runtime-generated values prevent a precomputed output from passing.
        base = 10 + secrets.randbelow(50)
        challenge = f"""timestamp,sensor_id,temperature,comments
2024-02-03T11:01:00,S1,{base + 10}.00,first
this physical line is malformed
2024-02-03T10:05:00,S2,,gap from prior physical record
2024-02-03T10:25:00,S2,{base + 10}.00,second
2024-02-03T12:02:00,S3,{base + 20}.00,third
2024-02-03T11:40:00,S1,,later gap
2024-02-03T12:30:00,S3,{base + 20}.00,"embedded
fragment without enough commas"
"""
        run_pipeline(challenge)

        # Exercise the required max == min normalization branch.
        equal_temp = 5 + secrets.randbelow(80)
        equal_case = f"""timestamp,sensor_id,temperature,comments
2025-07-09T08:00:00,A,{equal_temp}.00,start
2025-07-09T08:30:00,A,,gap
bad,physical,line
2025-07-09T09:00:00,B,{equal_temp}.00,same
2025-07-09T10:00:00,C,,same through gap
"""
        run_pipeline(equal_case)
    finally:
        with open(RAW_PATH, "w") as f:
            f.write(original_raw)
        if original_output is not None:
            with open(OUTPUT_PATH, "w") as f:
                if original_output:
                    f.write("\n".join(original_output) + "\n")
                else:
                    f.write("")


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
