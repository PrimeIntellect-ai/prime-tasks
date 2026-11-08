#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import random
import subprocess
import pytest


def filter_signal(arr):
    n = len(arr)
    if n == 0:
        return []
    out = []
    for i in range(n):
        window = []
        for j in range(i - 2, i + 3):
            idx = max(0, min(n - 1, j))
            window.append(arr[idx])
        out.append(str(max(window) - min(window)))
    return out


def test_extracted_signal():
    path = "/home/user/extracted_signal.txt"
    assert os.path.isfile(path), f"Missing extracted signal file at {path}"

    expected = []
    for t in range(120):
        expected.append(int(320 + 200 * math.sin(0.1 * t)))
    expected_str = " ".join(map(str, expected))

    with open(path, "r") as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, "The extracted signal does not match the expected telemetry data."


def test_legacy_filter_compiled():
    path = "/home/user/legacy_filter"
    assert os.path.isfile(path), f"Missing compiled legacy filter at {path}"
    assert os.access(path, os.X_OK), f"The legacy filter at {path} is not executable."


def test_reference_output():
    path = "/home/user/reference_output.txt"
    assert os.path.isfile(path), f"Missing reference output file at {path}"

    expected = []
    for t in range(120):
        expected.append(int(320 + 200 * math.sin(0.1 * t)))
    expected_out_str = " ".join(filter_signal(expected))

    with open(path, "r") as f:
        actual_out_str = f.read().strip()

    assert actual_out_str == expected_out_str, "The reference output does not match the expected filtered data."


def test_fast_filter_fuzz_equivalence():
    agent_script = "/home/user/fast_filter.py"
    assert os.path.isfile(agent_script), f"Missing optimized Python script at {agent_script}"

    random.seed(42)
    iterations = 100

    for i in range(iterations):
        length = random.randint(50, 5000)
        values = [random.randint(0, 1000) for _ in range(length)]
        input_data = " ".join(map(str, values))
        expected_out = " ".join(filter_signal(values))

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed or crashed on iteration {i}"
        agent_out = agent_proc.stdout.strip()

        if agent_out != expected_out:
            snippet = input_data[:100] + ("..." if len(input_data) > 100 else "")
            pytest.fail(
                f"Fuzz equivalence mismatch on iteration {i}.\n"
                f"Input length: {length}\n"
                f"Input snippet: {snippet}\n"
                f"Expected: {expected_out[:100]}...\n"
                f"Actual  : {agent_out[:100]}..."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
