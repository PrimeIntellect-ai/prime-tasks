#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import sys
import tempfile
import time

import pytest
import redis


def test_output_directory_and_acls():
    output_dir = "/home/user/output_data"
    assert os.path.isdir(output_dir), f"Directory {output_dir} does not exist."

    res = subprocess.run(["getfacl", output_dir], capture_output=True, text=True)
    assert res.returncode == 0, "Failed to run getfacl."

    output = res.stdout
    assert "user:nobody:r-x" in output, f"ACL user:nobody:r-x not found in getfacl output:\n{output}"
    assert "default:user:nobody:r--" in output, f"Default ACL default:user:nobody:r-- not found in getfacl output:\n{output}"


def test_optimized_processor_exists():
    script_path = "/home/user/optimized_processor.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."


def test_processor_low_disk_exit_code():
    script_path = "/home/user/optimized_processor.py"
    output_file = "/home/user/output_data/processed.jsonl"

    if os.path.exists(output_file):
        os.remove(output_file)

    with tempfile.TemporaryDirectory() as patch_dir:
        sitecustomize = os.path.join(patch_dir, "sitecustomize.py")
        with open(sitecustomize, "w") as f:
            f.write(r'''
import os
import shutil

_real_statvfs = os.statvfs
_DiskUsage = type(shutil.disk_usage("/"))

def low_disk_usage(path):
    return _DiskUsage(1024 * 1024 * 1024, 1024 * 1024 * 1024, 0)

def low_statvfs(path):
    values = list(_real_statvfs(path))
    values[3] = 0
    values[4] = 0
    return os.statvfs_result(values)

shutil.disk_usage = low_disk_usage
os.statvfs = low_statvfs
''')

        env = os.environ.copy()
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = patch_dir if not old_pythonpath else patch_dir + os.pathsep + old_pythonpath
        res = subprocess.run(
            [sys.executable, script_path],
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )

    assert res.returncode == 2, (
        f"Under simulated low disk space, expected exit code 2 but got {res.returncode}. "
        f"Stdout: {res.stdout} Stderr: {res.stderr}"
    )
    assert not os.path.exists(output_file), "Processor wrote output despite insufficient disk space."


def test_processor_execution_and_metric():
    script_path = "/home/user/optimized_processor.py"
    output_file = "/home/user/output_data/processed.jsonl"

    # The script appends to the file, so remove it before timing execution.
    if os.path.exists(output_file):
        os.remove(output_file)

    start = time.time()
    res = subprocess.run([sys.executable, script_path], capture_output=True, text=True)
    elapsed = time.time() - start

    assert res.returncode == 0, f"Script failed with exit code {res.returncode}. Stderr: {res.stderr}"
    assert elapsed <= 1.5, f"Metric threshold failed: Execution time {elapsed:.3f}s exceeded threshold of 1.5s."
    assert os.path.isfile(output_file), f"Output file {output_file} was not created."

    with open(output_file, "r") as f:
        lines = f.readlines()

    assert len(lines) == 50000, f"Expected 50000 lines in {output_file}, got {len(lines)}."

    try:
        r = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
        r.ping()
    except redis.ConnectionError:
        pytest.fail("Could not connect to Redis on 127.0.0.1:6379 to verify data.")

    keys = [f"sensor:{i}" for i in range(50000)]
    redis_values = r.mget(keys)
    assert all(value is not None for value in redis_values), "One or more required sensor keys are missing from Redis."

    parsed_lines = []
    seen_ids = set()
    for idx, line in enumerate(lines):
        line = line.strip()
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {idx} in {output_file} is not valid JSON: {line}")

        assert "id" in data, f"Missing 'id' in output line {idx}: {data}"
        assert "processed_value" in data, f"Missing 'processed_value' in output line {idx}: {data}"

        expected_id = f"sensor:{idx}"
        assert data["id"] == expected_id, (
            f"Line {idx} must contain id {expected_id}, got {data['id']}."
        )
        assert data["id"] not in seen_ids, f"Duplicate sensor ID in output: {data['id']}"
        seen_ids.add(data["id"])

        redis_data = json.loads(redis_values[idx])
        expected_value = redis_data["value"] * 1.5
        actual_value = data["processed_value"]
        assert abs(actual_value - expected_value) < 1e-6, (
            f"Value mismatch for {expected_id}: expected {expected_value}, got {actual_value}."
        )
        parsed_lines.append(data)

    assert seen_ids == set(keys), "Output does not contain every required sensor ID exactly once."

    # Preserve the original random sampled Redis-backed correctness assertions.
    indices = random.sample(range(50000), 100)
    for idx in indices:
        data = parsed_lines[idx]
        sensor_id = data["id"]
        redis_data_str = r.get(sensor_id)
        assert redis_data_str is not None, f"Key {sensor_id} not found in Redis."

        redis_data = json.loads(redis_data_str)
        expected_value = redis_data["value"] * 1.5
        actual_value = data["processed_value"]
        assert abs(actual_value - expected_value) < 1e-6, (
            f"Value mismatch for {sensor_id}: expected {expected_value}, got {actual_value}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
