#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import pytest

SCRIPT = Path("/home/user/process_telemetry.py")
INPUT = Path("/home/user/incoming/telemetry.jsonl")
AVERAGES = Path("/home/user/output/averages.json")
STATS = Path("/home/user/logs/pipeline_stats.json")


def test_averages_json():
    filepath = "/home/user/output/averages.json"
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did you create the output directory and save the file?"

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {filepath} is not valid JSON")

    expected = {
        "Alpha": 26.0,
        "Beta": 105.0,
        "Gamma": 50.0
    }

    assert data == expected, f"Contents of {filepath} do not match expected values. Expected {expected}, got {data}"


def test_pipeline_stats_json():
    filepath = "/home/user/logs/pipeline_stats.json"
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did you create the logs directory and save the file?"

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {filepath} is not valid JSON")

    expected = {
        "total_records_read": 10,
        "duplicates_dropped": 3,
        "unique_sensors_found": 3
    }

    assert data == expected, f"Contents of {filepath} do not match expected values. Expected {expected}, got {data}"


def test_script_executes_and_processes_unseen_input():
    assert SCRIPT.is_file(), f"Required script {SCRIPT} is missing"
    source = SCRIPT.read_text(encoding="utf-8")
    try:
        tree = ast.parse(source, filename=str(SCRIPT))
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    md5_reference = any(
        (isinstance(node, ast.Name) and node.id.lower() == "md5")
        or (isinstance(node, ast.Attribute) and node.attr.lower() == "md5")
        or (isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.lower() == "md5")
        for node in ast.walk(tree)
    )
    assert md5_reference, "The script does not reference the required MD5 hash algorithm"

    token = secrets.token_hex(8)
    sensor_a = f"{token}-ab"
    sensor_b = f"{token}-a"
    sensor_c = f"{token}-other"
    shared_time = f"shared-{token}"
    records = [
        {"sensor_id": sensor_a, "timestamp": "c", "value": 1.25},
        {"sensor_id": sensor_a, "timestamp": "c", "value": 999.0},
        {"sensor_id": sensor_b, "timestamp": "bc", "value": 8.0},
        {"sensor_id": sensor_a, "timestamp": shared_time, "value": 2.5},
        {"sensor_id": sensor_c, "timestamp": shared_time, "value": 20.0},
        {"sensor_id": sensor_b, "timestamp": f"later-{token}", "value": 12.0},
        {"sensor_id": sensor_b, "timestamp": f"later-{token}", "value": -500.0},
        {"sensor_id": sensor_c, "timestamp": f"final-{token}", "value": 24.0},
    ]

    seen = set()
    sums = {}
    counts = {}
    duplicates = 0
    for record in records:
        composite = f"{record['sensor_id']}|{record['timestamp']}"
        digest = hashlib.md5(composite.encode("utf-8")).hexdigest()
        if digest in seen:
            duplicates += 1
            continue
        seen.add(digest)
        sensor = record["sensor_id"]
        sums[sensor] = sums.get(sensor, 0.0) + record["value"]
        counts[sensor] = counts.get(sensor, 0) + 1

    expected_averages = {
        sensor: round(sums[sensor] / counts[sensor], 2)
        for sensor in sums
    }
    expected_stats = {
        "total_records_read": len(records),
        "duplicates_dropped": duplicates,
        "unique_sensors_found": len(sums),
    }

    paths = (INPUT, AVERAGES, STATS)
    backups = {path: path.read_bytes() if path.exists() else None for path in paths}
    try:
        INPUT.parent.mkdir(parents=True, exist_ok=True)
        INPUT.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")
        for path in (AVERAGES, STATS):
            if path.exists():
                path.unlink()

        result = subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Script failed on unseen input with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert AVERAGES.is_file(), f"Script did not create {AVERAGES}"
        assert STATS.is_file(), f"Script did not create {STATS}"

        try:
            actual_averages = json.loads(AVERAGES.read_text(encoding="utf-8"))
            actual_stats = json.loads(STATS.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            pytest.fail(f"Script produced invalid JSON: {exc}")

        assert actual_averages == expected_averages
        assert actual_stats == expected_stats
        assert set(actual_stats) == set(expected_stats)
        assert all(type(value) is int for value in actual_stats.values())
    finally:
        for path, content in backups.items():
            if content is None:
                if path.exists():
                    path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
