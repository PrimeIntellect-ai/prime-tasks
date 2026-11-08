#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import random
import pytest

def test_joblib_typo_fixed():
    """Verify that the typo 'cloudpcikle' has been fixed in setup files."""
    joblib_dir = "/app/joblib-1.3.2"
    setup_py_path = os.path.join(joblib_dir, "setup.py")
    setup_cfg_path = os.path.join(joblib_dir, "setup.cfg")

    typo_found = False

    if os.path.isfile(setup_py_path):
        with open(setup_py_path, 'r') as f:
            if "cloudpcikle" in f.read():
                typo_found = True

    if os.path.isfile(setup_cfg_path):
        with open(setup_cfg_path, 'r') as f:
            if "cloudpcikle" in f.read():
                typo_found = True

    assert not typo_found, "The deliberate typo 'cloudpcikle' is still present in setup.py or setup.cfg."

def generate_csv(num_rows, num_sensors):
    """Generate a random CSV matching the required schema."""
    lines = ["timestamp,sensor_id,metric_a,metric_b,metric_c"]
    sensors = [f"sens_{i:02d}" for i in range(1, num_sensors + 1)]
    for _ in range(num_rows):
        ts = random.randint(1690000000, 1690000000 + 100000)
        sensor = random.choice(sensors)
        ma = round(random.uniform(0, 100), 2)
        mb = round(random.uniform(0, 100), 2)
        mc = round(random.uniform(0, 100), 2)
        lines.append(f"{ts},{sensor},{ma},{mb},{mc}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle to ensure bit-exact output."""
    agent_script = "/home/user/analyze.py"
    oracle_script = "/tests/oracle_analyze.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)

    for i in range(50):
        num_rows = random.randint(50, 5000)
        num_sensors = random.randint(1, 20)
        csv_data = generate_csv(num_rows, num_sensors)

        # Run oracle
        proc_oracle = subprocess.run(
            [sys.executable, oracle_script],
            input=csv_data,
            text=True,
            capture_output=True
        )
        assert proc_oracle.returncode == 0, f"Oracle failed on iteration {i}:\n{proc_oracle.stderr}"
        oracle_out = proc_oracle.stdout

        # Run agent
        proc_agent = subprocess.run(
            [sys.executable, agent_script],
            input=csv_data,
            text=True,
            capture_output=True
        )
        assert proc_agent.returncode == 0, f"Agent script failed on iteration {i}:\n{proc_agent.stderr}"
        agent_out = proc_agent.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on iteration {i}!\n\n"
                f"Input CSV (first 500 chars):\n{csv_data[:500]}...\n\n"
                f"Oracle Output (first 500 chars):\n{oracle_out[:500]}...\n\n"
                f"Agent Output (first 500 chars):\n{agent_out[:500]}..."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
