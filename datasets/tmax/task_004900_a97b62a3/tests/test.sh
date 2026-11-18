#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import random
import tempfile
import subprocess
import pytest

def get_agent_entry_point():
    sh_path = "/home/user/etl_pipeline.sh"
    py_path = "/home/user/etl_pipeline.py"
    if os.path.isfile(sh_path) and os.access(sh_path, os.X_OK):
        return sh_path
    if os.path.isfile(py_path) and os.access(py_path, os.X_OK):
        return py_path
    if os.path.isfile(py_path):
        # If python file exists but not executable, we can try running it with python
        return "python3 " + py_path
    return None

def generate_csv(filepath):
    num_rows = random.randint(10, 50)
    timestamp = 1000
    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        for _ in range(num_rows):
            timestamp += random.randint(1, 10)
            txn_id = random.randint(101, 150)
            res_id = f"R{random.randint(1, 20)}"
            action = "REQUEST" if random.random() < 0.8 else "RELEASE"
            writer.writerow([timestamp, txn_id, res_id, action])

def normalize_json(output):
    try:
        data = json.loads(output)
        if "deadlocks" in data and isinstance(data["deadlocks"], list):
            data["deadlocks"] = sorted([sorted(cycle) for cycle in data["deadlocks"]])
        return data
    except Exception:
        return output.strip()

def test_fuzz_equivalence():
    agent_cmd = get_agent_entry_point()
    assert agent_cmd is not None, "Could not find executable /home/user/etl_pipeline.sh or /home/user/etl_pipeline.py"

    oracle_cmd = "/tests/oracle_etl"
    assert os.path.isfile(oracle_cmd) and os.access(oracle_cmd, os.X_OK), "Oracle binary not found or not executable"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            csv_path = os.path.join(tmpdir, f"input_{i}.csv")
            generate_csv(csv_path)

            # Run oracle
            oracle_res = subprocess.run([oracle_cmd, csv_path], capture_output=True, text=True)
            oracle_out = normalize_json(oracle_res.stdout)

            # Run agent
            if agent_cmd.startswith("python3 "):
                cmd_list = ["python3", agent_cmd.split(" ")[1], csv_path]
            else:
                cmd_list = [agent_cmd, csv_path]

            agent_res = subprocess.run(cmd_list, capture_output=True, text=True)
            agent_out = normalize_json(agent_res.stdout)

            if oracle_out != agent_out:
                with open(csv_path, 'r') as f:
                    input_content = f.read()
                pytest.fail(
                    f"Mismatch on fuzz input {i}!\n"
                    f"Input CSV:\n{input_content}\n"
                    f"Oracle Output:\n{oracle_res.stdout.strip()}\n"
                    f"Agent Output:\n{agent_res.stdout.strip()}\n"
                    f"Agent Stderr:\n{agent_res.stderr.strip()}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
