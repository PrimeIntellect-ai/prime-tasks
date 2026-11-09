#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import string
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/etl.py"
ORACLE_SCRIPT = "/tests/oracle_etl.py"

def generate_random_input(seed):
    random.seed(seed)
    num_strings = random.randint(10, 100)
    data = []
    for _ in range(num_strings):
        length = random.randint(20, 500)
        # Random ASCII characters
        s = ''.join(random.choices(string.ascii_letters + string.digits + string.punctuation + ' \t\n', k=length))
        data.append(s)
    return data

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    num_runs = 50
    for i in range(num_runs):
        input_data = generate_random_input(seed=4242 + i)

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
            json.dump(input_data, tmp)
            tmp_path = tmp.name

        try:
            # Run oracle
            oracle_res = subprocess.run(
                ["python3", ORACLE_SCRIPT, tmp_path],
                capture_output=True,
                text=True
            )
            assert oracle_res.returncode == 0, f"Oracle failed on run {i}:\n{oracle_res.stderr}"

            # Run agent
            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT, tmp_path],
                capture_output=True,
                text=True
            )
            assert agent_res.returncode == 0, f"Agent script failed on run {i}:\n{agent_res.stderr}"

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            if oracle_out != agent_out:
                pytest.fail(
                    f"Mismatch on run {i} (seed {4242 + i}).\n\n"
                    f"Oracle output:\n{oracle_out[:1000]}...\n\n"
                    f"Agent output:\n{agent_out[:1000]}..."
                )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
