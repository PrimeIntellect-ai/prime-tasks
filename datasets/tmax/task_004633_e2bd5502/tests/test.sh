#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import tempfile
import pytest

ORACLE_SCRIPT = "/tests/oracle_compute.sh"


def generate_random_signal(filepath):
    num_points = random.randint(10, 1000)
    header_id = ''.join(random.choices(string.ascii_letters + string.digits + "_", k=10))

    with open(filepath, 'w') as f:
        f.write(f">{header_id}\n")
        t = 0.0
        for _ in range(num_points):
            y = random.uniform(-100.0, 100.0)
            f.write(f"{t:.6f} {y:.6f}\n")
            t += random.uniform(0.01, 1.5)


def test_fuzz_equivalence():
    agent_script = "/home/user/compute_integral.sh"

    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"
    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"

    random.seed(42)
    num_tests = 500

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_tests):
            test_file = os.path.join(tmpdir, f"test_{i}.dat")
            generate_random_signal(test_file)

            oracle_cmd = ["bash", ORACLE_SCRIPT, test_file]
            agent_cmd = ["bash", agent_script, test_file]

            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert oracle_res.returncode == 0, f"Oracle failed on input {test_file}"
            assert agent_res.returncode == 0, f"Agent script failed on input {test_file}\nError: {agent_res.stderr}"

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            if oracle_out != agent_out:
                with open(test_file, 'r') as f:
                    input_content = f.read()
                pytest.fail(f"Mismatch on test {i}!\nInput:\n{input_content[:500]}...\nOracle: {oracle_out}\nAgent: {agent_out}")


def test_flow_script():
    test_flow_script = "/home/user/test_flow.sh"
    assert os.path.isfile(test_flow_script), f"Wrapper script not found at {test_flow_script}"

    res = subprocess.run(["bash", test_flow_script], capture_output=True, text=True)
    assert res.returncode == 0, f"test_flow.sh failed with error: {res.stderr}"

    redis_res = subprocess.run(["redis-cli", "-p", "6379", "GET", "integral:test1"], capture_output=True, text=True)
    assert redis_res.returncode == 0, "Failed to query Redis"
    redis_val = redis_res.stdout.strip()

    signal_file = "/app/signals/test1"
    if not os.path.exists(signal_file):
        pytest.skip("Signal file /app/signals/test1 not found, cannot verify Redis value.")

    oracle_res = subprocess.run(["bash", ORACLE_SCRIPT, signal_file], capture_output=True, text=True)
    expected_val = oracle_res.stdout.strip()

    assert redis_val == expected_val, f"Redis value '{redis_val}' does not match expected '{expected_val}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
