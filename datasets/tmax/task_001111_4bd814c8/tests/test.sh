#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest
import urllib.request
import urllib.error

EXPECTED = [1.0 + i * 0.05 for i in range(100)]

def read_floats(path):
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 100, f"Expected 100 lines in {path}, found {len(lines)}."
    try:
        return [float(line) for line in lines], lines
    except ValueError as e:
        pytest.fail(f"Invalid float in {path}: {e}")

def test_dataset_downloaded():
    path = '/home/user/dataset.txt'
    assert os.path.isfile(path), f"Dataset file {path} is missing."
    values, _ = read_floats(path)
    assert values == EXPECTED, "Downloaded dataset does not contain the intended Redis values."

def test_services_running_and_proxying():
    try:
        req = urllib.request.Request('http://localhost:8080/dataset')
        with urllib.request.urlopen(req, timeout=5) as response:
            lines = response.read().decode('utf-8').strip().split('\n')
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to fetch dataset from http://localhost:8080/dataset: {e}")

    assert len(lines) == 100, f"Expected 100 lines from API, got {len(lines)}."
    try:
        values = [float(line) for line in lines]
    except ValueError as e:
        pytest.fail(f"API returned an invalid float: {e}")
    assert values == EXPECTED, "API does not serve the intended Redis values."

    _, local_lines = read_floats('/home/user/dataset.txt')
    assert lines == local_lines, "Data from API does not match /home/user/dataset.txt"

def expected_output(seed, B, dataset):
    result = subprocess.run(
        ['/tests/oracle_bootstrapper', str(seed), str(B)],
        capture_output=True, text=True, timeout=5, check=True
    )
    return result.stdout.strip()

def test_bootstrapper_binary_exists():
    path = '/home/user/bootstrapper'
    assert os.path.isfile(path), f"Compiled binary {path} is missing."
    assert os.access(path, os.X_OK), f"Binary {path} is not executable."

def test_fuzz_equivalence():
    agent_binary = '/home/user/bootstrapper'
    oracle_binary = '/tests/oracle_bootstrapper'
    assert os.path.isfile(oracle_binary) and os.access(oracle_binary, os.X_OK)

    random.seed(42)
    for _ in range(20):
        seed = random.randint(1, 100000)
        B = random.randint(1000, 5000)
        try:
            agent = subprocess.run(
                [agent_binary, str(seed), str(B)], capture_output=True,
                text=True, timeout=5, check=True
            ).stdout.strip()
            oracle = subprocess.run(
                [oracle_binary, str(seed), str(B)], capture_output=True,
                text=True, timeout=5, check=True
            ).stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Bootstrapper failed on input {seed} {B}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Bootstrapper timed out on input {seed} {B}")
        assert agent == oracle, (
            f"Mismatch on inputs seed={seed}, B={B}.\nExpected: {oracle}\nGot: {agent}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
