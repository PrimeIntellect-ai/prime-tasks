#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import json

def test_bright_frames_count():
    bright_frames_path = "/home/user/bright_frames.txt"
    assert os.path.isfile(bright_frames_path), f"File not found: {bright_frames_path}"
    with open(bright_frames_path, "r") as f:
        content = f.read().strip()

    assert content == "45", f"Expected bright_frames.txt to contain '45', but got '{content}'"

def test_scaler_fuzz_equivalence():
    oracle_path = "/oracle/scaler"
    agent_path = "/home/user/scaler/target/release/scaler"

    assert os.path.isfile(agent_path), f"Agent executable not found: {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent executable is not executable: {agent_path}"
    assert os.path.isfile(oracle_path), f"Oracle executable not found: {oracle_path}"

    random.seed(42)

    for i in range(200):
        n_rows = random.randint(10, 200)
        csv_lines = ["group,value"]
        for _ in range(n_rows):
            group = random.choice([0, 1])
            value = random.uniform(-1000.0, 1000.0)
            csv_lines.append(f"{group},{value}")

        csv_input = "\n".join(csv_lines) + "\n"

        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"

        # Run agent
        agent_proc = subprocess.run(
            [agent_path],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent failed on iteration {i}:\n{agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        if oracle_out != agent_out:
            try:
                oracle_json = json.loads(oracle_out)
                agent_json = json.loads(agent_out)
                assert len(oracle_json) == len(agent_json), f"Length mismatch on iteration {i}. Oracle: {len(oracle_json)}, Agent: {len(agent_json)}"
                for j, (o_val, a_val) in enumerate(zip(oracle_json, agent_json)):
                    assert abs(o_val - a_val) < 1e-5, f"Value mismatch at index {j} on iteration {i}. Oracle: {o_val}, Agent: {a_val}"
            except Exception:
                assert oracle_out == agent_out, f"Mismatch on iteration {i}.\nInput:\n{csv_input}\nOracle:\n{oracle_out}\nAgent:\n{agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
