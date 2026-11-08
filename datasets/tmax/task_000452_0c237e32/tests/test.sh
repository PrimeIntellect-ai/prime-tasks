#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import tempfile
import pytest

AGENT_EXE = "/home/user/etl_query"
ORACLE_EXE = "/tests/etl_oracle"

def test_executable_exists():
    assert os.path.isfile(AGENT_EXE), f"Agent executable not found at {AGENT_EXE}"
    assert os.access(AGENT_EXE, os.X_OK), f"Agent executable {AGENT_EXE} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_EXE), f"Oracle not found at {ORACLE_EXE}"
    assert os.access(ORACLE_EXE, os.X_OK), f"Oracle {ORACLE_EXE} is not executable"
    random.seed(42)
    nodes = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"]

    for i in range(50):
        edge_count = random.randint(50, 200)
        edges = []
        for _ in range(edge_count):
            edges.append({
                "from": random.choice(nodes),
                "to": random.choice(nodes),
                "weight": random.randint(10, 50)
            })

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tmp:
            json.dump(edges, tmp)
            tmp_path = tmp.name

        try:
            oracle_proc = subprocess.run(
                [ORACLE_EXE, tmp_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on input {tmp_path}: {oracle_proc.stderr}"

            agent_proc = subprocess.run(
                [AGENT_EXE, tmp_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            if agent_proc.returncode != 0:
                pytest.fail(f"Agent failed on input {tmp_path}.\nStderr: {agent_proc.stderr}")

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()
            if oracle_out != agent_out:
                pytest.fail(
                    f"Output mismatch on run {i+1}!\n"
                    f"Input file: {tmp_path}\n"
                    f"Oracle output:\n{oracle_out}\n"
                    f"Agent output:\n{agent_out}"
                )
        finally:
            os.remove(tmp_path)

def test_deadlock_fix():
    pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
