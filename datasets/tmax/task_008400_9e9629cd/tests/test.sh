#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import random
import secrets
import subprocess
from datetime import datetime, timedelta, timezone
import pytest

SCRIPT_PATH = "/home/user/process_pipeline.py"
INPUT_PATH = "/home/user/input/readings.tsv"
OUTPUT_PATH = "/home/user/anomalies.json"


def compute_expected_anomalies(input_file):
    if not os.path.isfile(input_file):
        pytest.fail(f"Input file {input_file} is missing.")

    seen_hashes = set()
    deduplicated_records = []

    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            raw_string = line.rstrip('\n')
            if not raw_string:
                continue

            line_hash = hashlib.sha256(raw_string.encode('utf-8')).hexdigest()
            if line_hash in seen_hashes:
                continue
            seen_hashes.add(line_hash)

            parts = raw_string.split('\t')
            if len(parts) >= 3:
                timestamp = parts[0]
                device_id = parts[1]
                payload_str = '\t'.join(parts[2:])
                try:
                    payload = json.loads(payload_str)
                    temperature = float(payload.get('temperature', 0.0))
                    deduplicated_records.append((timestamp, device_id, temperature))
                except json.JSONDecodeError:
                    pass

    # Group by device_id
    devices = {}
    for ts, dev, temp in deduplicated_records:
        if dev not in devices:
            devices[dev] = []
        devices[dev].append((ts, temp))

    expected_anomalies = {}
    for dev, records in devices.items():
        # Sort chronologically by timestamp
        records.sort(key=lambda x: x[0])

        for i in range(3, len(records)):
            prev_3 = records[i-3:i]
            mean_temp = sum(r[1] for r in prev_3) / 3.0
            current_temp = records[i][1]
            if current_temp - mean_temp >= 10.0:
                expected_anomalies[dev] = records[i][0]
                break

    return expected_anomalies


def run_script_and_check(input_path):
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Running {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} was not created."
    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON after running the script.")

    expected = compute_expected_anomalies(input_path)
    assert actual == expected, (
        "The script produced incorrect anomalies when executed.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def make_generated_fixture():
    token = secrets.token_hex(6)
    base = float(secrets.randbelow(31) - 10)
    start = datetime(
        2024 + secrets.randbelow(2),
        1 + secrets.randbelow(12),
        1 + secrets.randbelow(20),
        secrets.randbelow(12),
        0,
        0,
        tzinfo=timezone.utc,
    )

    def ts(minutes):
        return (start + timedelta(minutes=minutes)).strftime('%Y-%m-%dT%H:%M:%SZ')

    def line(device, minute, temperature, style=0):
        if style == 0:
            payload = json.dumps({"temperature": temperature, "humidity": 40}, separators=(",", ":"))
        else:
            payload = json.dumps({"humidity": 40, "temperature": temperature}, separators=(", ", ": "))
        return f"{ts(minute)}\t{device}\t{payload}"

    exact_hash_device = f"HASH_{token}"
    semantic_duplicate_device = f"RAW_{token}"
    strict_device = f"STRICT_{token}"
    first_device = f"FIRST_{token}"
    quiet_device = f"QUIET_{token}"

    exact_duplicate = line(exact_hash_device, 1, base + 30)
    lines = [
        line(exact_hash_device, 3, base + 20),
        exact_duplicate,
        line(exact_hash_device, 0, base),
        exact_duplicate,
        line(exact_hash_device, 2, base),

        # These two records have equal fields but different raw strings and must both remain.
        line(semantic_duplicate_device, 0, base),
        line(semantic_duplicate_device, 1, base + 30, 0),
        line(semantic_duplicate_device, 1, base + 30, 1),
        line(semantic_duplicate_device, 2, base),
        line(semantic_duplicate_device, 3, base + 20),

        line(strict_device, 0, base),
        line(strict_device, 1, base),
        line(strict_device, 2, base),
        line(strict_device, 3, base + 9.999),
        line(strict_device, 4, base + 30),

        line(first_device, 0, base),
        line(first_device, 1, base),
        line(first_device, 2, base),
        line(first_device, 3, base + 10),
        line(first_device, 4, base + 50),

        line(quiet_device, 0, base + 1),
        line(quiet_device, 1, base + 2),
    ]
    random.SystemRandom().shuffle(lines)
    return '\n'.join(lines) + '\n'


def test_anomalies_json_exists():
    """Check if the output JSON file is generated."""
    output_path = "/home/user/anomalies.json"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."


def test_anomalies_json_content():
    """Check if the output JSON file contains the correct anomalies based on the input data."""
    output_path = "/home/user/anomalies.json"
    input_path = "/home/user/input/readings.tsv"

    assert os.path.isfile(output_path), f"The output file {output_path} is missing."

    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            actual_anomalies = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    expected_anomalies = compute_expected_anomalies(input_path)

    assert actual_anomalies == expected_anomalies, (
        f"The anomalies in {output_path} do not match the expected results.\n"
        f"Expected: {expected_anomalies}\n"
        f"Actual: {actual_anomalies}"
    )


def test_script_exists():
    """Check if the process_pipeline.py script was created."""
    script_path = "/home/user/process_pipeline.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_script_executes_pipeline_on_runtime_inputs():
    """Execute the submitted script and exercise the required pipeline on fresh inputs."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    with open(INPUT_PATH, 'rb') as f:
        original_input = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            original_output = f.read()

    try:
        # First prove that the submitted artifact itself regenerates the supplied result.
        run_script_and_check(INPUT_PATH)

        # Runtime-generated fixtures prevent a precomputed fixed-fixture answer from passing.
        for _ in range(2):
            fixture = make_generated_fixture()
            with open(INPUT_PATH, 'w', encoding='utf-8', newline='') as f:
                f.write(fixture)
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            run_script_and_check(INPUT_PATH)
    finally:
        with open(INPUT_PATH, 'wb') as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
