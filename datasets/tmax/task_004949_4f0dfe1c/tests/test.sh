#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import tempfile
import csv

def generate_random_csv(filepath, num_rows):
    headers = ["source_id", "target_id", "amount", "timestamp", "transaction_type"]
    types = ["TRANSFER", "PAYMENT", "REFUND", "FEE"]

    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        for _ in range(num_rows):
            src_len = random.randint(3, 5)
            tgt_len = random.randint(3, 5)
            src = ''.join(random.choices(string.ascii_letters + string.digits, k=src_len))
            tgt = ''.join(random.choices(string.ascii_letters + string.digits, k=tgt_len))
            amount = round(random.uniform(10.0, 5000.0), 2)
            timestamp = random.randint(1600000000, 1700000000)
            txn_type = random.choice(types)
            writer.writerow([src, tgt, amount, timestamp, txn_type])

def test_fuzz_equivalence():
    oracle_path = "/app/analyzer_oracle"
    agent_script = "/home/user/graph_pipeline.py"

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"

    random.seed(42)
    num_tests = 500

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_tests):
            csv_path = os.path.join(tmpdir, f"test_{i}.csv")
            num_rows = random.randint(10, 500)
            generate_random_csv(csv_path, num_rows)

            # Run oracle
            try:
                oracle_result = subprocess.run(
                    [oracle_path, csv_path],
                    capture_output=True,
                    text=True,
                    check=True
                )
                oracle_out = oracle_result.stdout.strip()
            except subprocess.CalledProcessError as e:
                oracle_out = f"ORACLE ERROR: {e.stderr}"

            # Run agent
            try:
                agent_result = subprocess.run(
                    ["python3", agent_script, csv_path],
                    capture_output=True,
                    text=True,
                    check=True
                )
                agent_out = agent_result.stdout.strip()
            except subprocess.CalledProcessError as e:
                agent_out = f"AGENT ERROR: {e.stderr}"

            assert oracle_out == agent_out, (
                f"Mismatch on test {i} with {num_rows} rows.\n"
                f"CSV Path: {csv_path}\n"
                f"Oracle Output:\n{oracle_out}\n"
                f"Agent Output:\n{agent_out}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
