#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def generate_csv(seed):
    random.seed(seed)
    rows = random.randint(5, 50)
    cols = random.randint(3, 10)

    csv_lines = []
    for _ in range(rows):
        row_vals = []
        for _ in range(cols):
            if random.random() < 0.10:
                row_vals.append("NaN")
            else:
                val = random.uniform(-100.0, 100.0)
                row_vals.append(f"{val:.6f}")
        csv_lines.append(",".join(row_vals))
    return "\n".join(csv_lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/app/dataset_cleaner"
    agent_script = "/home/user/replicate.py"
    agent_cmd = ["python3", agent_script]

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    N = 100
    for i in range(N):
        csv_input = generate_csv(seed=1000 + i)

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=csv_input,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle binary failed on fuzz case {i}. Stderr:\n{e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on fuzz case {i}.")

        # Run agent
        try:
            agent_proc = subprocess.run(
                agent_cmd,
                input=csv_input,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            agent_out = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on fuzz case {i}. Stderr:\n{e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on fuzz case {i}.")

        if oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on fuzz case {i}!\n\n"
                f"--- Input CSV ---\n{csv_input}\n"
                f"--- Oracle Output ---\n{oracle_out}\n"
                f"--- Agent Output ---\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
