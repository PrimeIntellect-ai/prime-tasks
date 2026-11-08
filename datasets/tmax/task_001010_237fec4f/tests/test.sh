#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import csv
import tempfile
import json

def test_pipeline_fuzz_equivalence():
    agent_script = "/home/user/pipeline.py"
    oracle_script = "/tests/oracle_pipeline.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)
    N = 50

    for i in range(N):
        num_rows = random.randint(50, 500)

        # Generate random CSV
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.csv') as tmp:
            csv_path = tmp.name
            writer = csv.writer(tmp)
            writer.writerow(["timestamp", "sensor_id", "value"])
            for _ in range(num_rows):
                t = round(random.uniform(0.0, 100.0), 3)
                sid = random.choice(["S1", "S2", "S3", "S4"])
                val = round(random.uniform(-50.0, 50.0), 3)
                writer.writerow([t, sid, val])

        try:
            # Run oracle
            oracle_cmd = ["python3", oracle_script, csv_path]
            oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_proc.returncode == 0, f"Oracle failed on input {csv_path}:\n{oracle_proc.stderr}"
            oracle_out = oracle_proc.stdout.strip()

            # Run agent
            agent_cmd = ["python3", agent_script, csv_path]
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

            if agent_proc.returncode != 0:
                with open(csv_path, 'r') as f:
                    csv_content = f.read()
                assert False, f"Agent program failed with exit code {agent_proc.returncode}.\nSTDERR:\n{agent_proc.stderr}\nINPUT CSV:\n{csv_content}"

            agent_out = agent_proc.stdout.strip()

            if oracle_out != agent_out:
                # Try to parse as JSON to compare structurally if possible, to avoid string formatting issues
                try:
                    oracle_json = json.loads(oracle_out)
                    agent_json = json.loads(agent_out)
                    if oracle_json == agent_json:
                        continue
                except Exception:
                    pass

                with open(csv_path, 'r') as f:
                    csv_content = f.read()

                assert False, (
                    f"Output mismatch on random input {i+1}/{N}.\n"
                    f"INPUT CSV:\n{csv_content}\n"
                    f"ORACLE OUTPUT:\n{oracle_out}\n"
                    f"AGENT OUTPUT:\n{agent_out}\n"
                )
        finally:
            if os.path.exists(csv_path):
                os.remove(csv_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
