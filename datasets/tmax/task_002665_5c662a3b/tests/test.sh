#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_csv(seed):
    random.seed(seed)
    lines = ["ts,dev,val"]
    num_lines = random.randint(50, 200)
    for _ in range(num_lines):
        ts = random.randint(1600000000, 1600020000)
        dev = random.choice(["D1", "D2", "D3", "D4", "D5"])
        if random.random() < 0.2:
            val = ""
        else:
            val = f"{random.uniform(0.0, 100.0):.2f}"
        lines.append(f"{ts},{dev},{val}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/etl.sh"
    oracle_script = "/tests/oracle.sh"

    assert os.path.isfile(agent_script), f"{agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"{agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Verifier oracle {oracle_script} does not exist."

    for i in range(50):
        csv_data = generate_csv(i)

        proc_oracle = subprocess.run(["/bin/bash", oracle_script], input=csv_data, text=True, capture_output=True)
        assert proc_oracle.returncode == 0, f"Oracle failed on run {i}."

        proc_agent = subprocess.run([agent_script], input=csv_data, text=True, capture_output=True)

        if proc_agent.returncode != 0:
            pytest.fail(f"Agent script failed (exit code {proc_agent.returncode}) on run {i}.\nStderr: {proc_agent.stderr}")

        oracle_out = proc_oracle.stdout.strip()
        agent_out = proc_agent.stdout.strip()

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on run {i}.\n"
                f"Input:\n{csv_data[:200]}...\n\n"
                f"Oracle Output:\n{oracle_out}\n\n"
                f"Agent Output:\n{agent_out}"
            )

def test_cron_file():
    cron_file = "/home/user/cron.txt"
    assert os.path.isfile(cron_file), f"{cron_file} does not exist."

    with open(cron_file, "r") as f:
        content = f.read().strip()

    assert "15" in content or "*/15" in content or "0,15,30,45" in content, "Cron expression does not appear to run every 15 minutes."
    assert "/home/user/etl.sh" in content, "Cron expression does not call /home/user/etl.sh."
    assert "<" in content and "/data/in.csv" in content, "Cron expression does not properly redirect input from /data/in.csv."
    assert ">" in content and "/data/out.jsonl" in content, "Cron expression does not properly redirect output to /data/out.jsonl."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
