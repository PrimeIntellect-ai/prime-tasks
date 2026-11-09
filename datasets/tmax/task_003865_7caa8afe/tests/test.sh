#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import tempfile
import json
import pytest

AGENT_SCRIPT = "/home/user/fixed_analyze.sh"
ORACLE_SCRIPT = "/tests/oracle_reference.sh"

def test_agent_script_exists_and_executable():
    """Ensure the agent script exists and is executable."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable"

def generate_random_csv(filepath):
    """Generate a random CSV matching the fuzz input distribution."""
    nodes = ['A', 'B', 'C', 'D', 'E']
    num_rows = random.randint(10, 100)

    with open(filepath, 'w') as f:
        f.write("tx_id,time,source_node,target_node,region_id,amount\n")
        for _ in range(num_rows):
            tx_id = random.randint(1, 1000)
            time_val = random.randint(1600000000, 1600005000)
            source_node = random.choice(nodes)
            target_node = random.choice(nodes)
            region_id = random.randint(1, 5)
            amount = round(random.uniform(10.0, 500.0), 2)
            f.write(f"{tx_id},{time_val},{source_node},{target_node},{region_id},{amount}\n")

def test_fuzz_equivalence():
    """Test the agent script against the oracle script on 100 random inputs."""
    random.seed(42)

    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            csv_path = os.path.join(tmpdir, f"input_{i}.csv")
            generate_random_csv(csv_path)

            # Run oracle
            oracle_proc = subprocess.run(
                ["bash", ORACLE_SCRIPT, csv_path],
                capture_output=True,
                text=True
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"

            # Run agent
            agent_proc = subprocess.run(
                [AGENT_SCRIPT, csv_path],
                capture_output=True,
                text=True
            )

            assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_proc.stderr}"

            oracle_output = oracle_proc.stdout.strip()
            agent_output = agent_proc.stdout.strip()

            # Compare parsed JSON to avoid superficial whitespace differences
            try:
                oracle_json = json.loads(oracle_output)
            except json.JSONDecodeError:
                pytest.fail(f"Oracle output is not valid JSON on iteration {i}:\n{oracle_output}")

            try:
                agent_json = json.loads(agent_output)
            except json.JSONDecodeError:
                pytest.fail(f"Agent output is not valid JSON on iteration {i}:\n{agent_output}")

            assert agent_json == oracle_json, (
                f"Mismatch on iteration {i}.\n"
                f"Input CSV:\n{open(csv_path).read()}\n"
                f"Expected JSON (Oracle):\n{json.dumps(oracle_json, indent=2)}\n"
                f"Got JSON (Agent):\n{json.dumps(agent_json, indent=2)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
