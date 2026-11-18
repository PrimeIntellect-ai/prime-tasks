#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/pipeline.py"
ORACLE_SCRIPT = "/tests/oracle_pipeline.py"

def generate_csv_input(num_rows=20):
    lines = ["id,event_name,timestamp,value"]
    for _ in range(num_rows):
        id_val = random.randint(1, 1000)
        event_name = "".join(random.choices(string.ascii_letters, k=random.randint(5, 10)))
        timestamp = random.randint(1600000000, 1700000000)
        if random.random() < 0.2:
            value = ""
        else:
            value = str(random.randint(-100, 100))
        lines.append(f"{id_val},{event_name},{timestamp},{value}")
    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)
    num_tests = 50

    for i in range(num_tests):
        num_rows = random.randint(5, 50)
        csv_input = generate_csv_input(num_rows)

        oracle_proc = subprocess.run(
            [ORACLE_SCRIPT],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle script failed on test {i}:\n{oracle_proc.stderr}"

        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on test {i}:\n{agent_proc.stderr}"

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on test {i}.\n"
            f"Input CSV:\n{csv_input}\n"
            f"Expected Output (Oracle):\n{oracle_proc.stdout}\n"
            f"Actual Output (Agent):\n{agent_proc.stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
