#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import datetime
import secrets
import subprocess
import pytest

SCRIPT = "/home/user/pipeline.py"
OUTPUT = "/home/user/output/valid_configs.csv"
INPUT_FILES = [
    "/home/user/data/service_a.jsonl",
    "/home/user/data/service_b.jsonl",
]

def align_timestamp(ts_str):
    # Parse ISO8601, e.g., 2023-10-25T14:30:07Z
    ts_str = ts_str.replace("Z", "+00:00")
    dt = datetime.datetime.fromisoformat(ts_str)
    # Round down to nearest 10 seconds
    dt = dt.replace(second=(dt.second // 10) * 10, microsecond=0)
    return dt.isoformat().replace("+00:00", "Z")

def is_valid_record(key, value):
    if key == "memory_limit":
        return isinstance(value, int) and not isinstance(value, bool) and 128 <= value <= 2048
    elif key == "cpu_cores":
        return isinstance(value, int) and not isinstance(value, bool) and value in (1, 2, 4, 8)
    elif key == "maintenance_mode":
        return isinstance(value, bool)
    return False

def get_expected_records():
    files = [
        "/home/user/data/service_a.jsonl",
        "/home/user/data/service_b.jsonl"
    ]
    records = []
    for f in files:
        if not os.path.exists(f):
            continue
        with open(f, "r") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                data = json.loads(line)
                key = data.get("key")
                value = data.get("value")
                if is_valid_record(key, value):
                    aligned_ts = align_timestamp(data["timestamp"])
                    records.append({
                        "aligned_ts": aligned_ts,
                        "service": data["service"],
                        "key": key,
                        "value": str(value)
                    })

    # Sort by aligned_ts, service, key
    records.sort(key=lambda x: (x["aligned_ts"], x["service"], x["key"]))
    return records

def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"pipeline.py exited with status {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/pipeline.py"), "The script /home/user/pipeline.py does not exist."

def test_pipeline_executes_on_provided_inputs():
    run_pipeline()

def test_output_csv_exists():
    assert os.path.isfile("/home/user/output/valid_configs.csv"), "The output file /home/user/output/valid_configs.csv does not exist."

def test_output_csv_content():
    output_file = "/home/user/output/valid_configs.csv"
    assert os.path.isfile(output_file), "Cannot test content, output file missing."

    expected_records = get_expected_records()

    with open(output_file, "r", newline="") as fh:
        reader = csv.reader(fh)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("The output CSV is empty (missing headers).")

        assert headers == ["aligned_ts", "service", "key", "value"], "CSV headers do not match the expected schema."

        actual_records = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Row {row} does not have exactly 4 columns."
            actual_records.append({
                "aligned_ts": row[0],
                "service": row[1],
                "key": row[2],
                "value": row[3]
            })

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} rows, but got {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual["aligned_ts"] == expected["aligned_ts"], f"Row {i+1}: expected aligned_ts {expected['aligned_ts']}, got {actual['aligned_ts']}"
        assert actual["service"] == expected["service"], f"Row {i+1}: expected service {expected['service']}, got {actual['service']}"
        assert actual["key"] == expected["key"], f"Row {i+1}: expected key {expected['key']}, got {actual['key']}"
        # values like True might be printed as 'True' or 'true', let's be case-insensitive for booleans if needed, but the prompt expects 'True' for Python bools or standard string representations.
        # We will compare lowercase to be safe against 'True' vs 'true'
        assert actual["value"].lower() == expected["value"].lower(), f"Row {i+1}: expected value {expected['value']}, got {actual['value']}"

def test_pipeline_on_changed_inputs():
    token = secrets.token_hex(8)
    original_inputs = {}
    for path in INPUT_FILES:
        with open(path, "rb") as fh:
            original_inputs[path] = fh.read()
    original_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as fh:
            original_output = fh.read()

    service_a = [
        {"timestamp": "2041-06-03T09:08:19Z", "service": f"zeta-{token}", "key": "memory_limit", "value": 128},
        {"timestamp": "2041-06-03T09:08:01Z", "service": f"alpha-{token}", "key": "cpu_cores", "value": 8},
        {"timestamp": "2041-06-03T09:08:29Z", "service": f"mid-{token}", "key": "maintenance_mode", "value": False},
        {"timestamp": "2041-06-03T09:08:31Z", "service": f"bad-{token}", "key": "memory_limit", "value": True},
        {"timestamp": "2041-06-03T09:08:32Z", "service": f"bad-{token}", "key": "cpu_cores", "value": 3},
        {"timestamp": "2041-06-03T09:08:33Z", "service": f"bad-{token}", "key": "other", "value": 512},
    ]
    service_b = [
        {"timestamp": "2041-06-03T09:07:59Z", "service": f"omega-{token}", "key": "memory_limit", "value": 2048},
        {"timestamp": "2041-06-03T09:08:06Z", "service": f"beta-{token}", "key": "cpu_cores", "value": 1},
        {"timestamp": "2041-06-03T09:08:24Z", "service": f"aardvark-{token}", "key": "maintenance_mode", "value": True},
        {"timestamp": "2041-06-03T09:08:34Z", "service": f"bad-{token}", "key": "memory_limit", "value": 2049},
        {"timestamp": "2041-06-03T09:08:35Z", "service": f"bad-{token}", "key": "maintenance_mode", "value": "true"},
        {"timestamp": "2041-06-03T09:08:36Z", "service": f"bad-{token}", "key": "cpu_cores", "value": True},
    ]

    try:
        for path, records in zip(INPUT_FILES, [service_a, service_b]):
            with open(path, "w") as fh:
                for record in records:
                    fh.write(json.dumps(record) + "\n")

        run_pipeline()
        test_output_csv_exists()
        test_output_csv_content()
    finally:
        for path, content in original_inputs.items():
            with open(path, "wb") as fh:
                fh.write(content)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        if original_output is not None:
            os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
            with open(OUTPUT, "wb") as fh:
                fh.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
