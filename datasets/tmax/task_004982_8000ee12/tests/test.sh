#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import time
import subprocess
import pytest

SCRIPT_PATH = "/home/user/optimized.sh"
RESULT_PATH = "/home/user/result.json"
EXPECTED_CMD = "jq -s '[.[] | select(.status==\"active\")] | group_by(.department) | map({department: .[0].department, total_salary: (map(.salary) | add)}) | sort_by(.total_salary) | reverse | .[0:5]' /app/data.jsonl"


def compute_expected_json():
    try:
        expected_out = subprocess.check_output(EXPECTED_CMD, shell=True, text=True)
        return json.loads(expected_out)
    except Exception as e:
        pytest.fail(f"Failed to compute expected JSON: {e}")


def load_result_json():
    assert os.path.isfile(RESULT_PATH), f"Missing result file: {RESULT_PATH}"
    with open(RESULT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} does not contain valid JSON.")


def remove_existing_result():
    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass


def test_optimized_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Missing optimized script: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_result_json_correctness():
    remove_existing_result()
    completed = subprocess.run([SCRIPT_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert completed.returncode == 0, f"Optimized script exited with status {completed.returncode}."

    agent_json = load_result_json()
    expected_json = compute_expected_json()
    assert agent_json == expected_json, "The output JSON does not match the expected JSON output."


def test_performance_speedup():
    baseline_script = "/app/baseline.sh"
    agent_script = SCRIPT_PATH

    # Measure baseline time
    start = time.time()
    subprocess.run([baseline_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    baseline_time = time.time() - start

    # Remove any precomputed output so the timed invocation must produce it.
    remove_existing_result()

    # Measure agent time
    start = time.time()
    completed = subprocess.run([agent_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    agent_time = time.time() - start

    assert completed.returncode == 0, f"Optimized script exited with status {completed.returncode}."

    # Confirm that the timed invocation generated the correct result.
    agent_json = load_result_json()
    expected_json = compute_expected_json()
    assert agent_json == expected_json, "The output JSON produced by the timed script does not match the expected JSON output."

    # Prevent division by zero
    agent_time = max(agent_time, 1e-6)

    speedup = baseline_time / agent_time

    assert speedup >= 15.0, f"Speedup threshold not met. Baseline: {baseline_time:.2f}s, Agent: {agent_time:.2f}s, Speedup: {speedup:.2f}x (Threshold: 15.0x)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
