#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile
import csv
import math

def test_repl_matches_oracle():
    oracle_path = "/app/stat_oracle"
    repl_path = "/home/user/repl"

    assert os.path.exists(repl_path), f"Agent executable {repl_path} is missing."
    assert os.access(repl_path, os.X_OK), f"Agent file {repl_path} is not executable."

    num_tests = 50
    max_diff = 0.0

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_tests):
            csv_file = os.path.join(tmpdir, f"test_{i}.csv")

            # Generate random CSV data
            with open(csv_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['id', 'group', 'val_A', 'val_B'])

                # Ensure enough valid rows for both groups
                for j in range(100):
                    group = random.choice(['control', 'treatment'])
                    # Mix of positive and negative to test filtering
                    val_a = random.uniform(-10.0, 100.0)
                    val_b = random.uniform(-10.0, 100.0)
                    writer.writerow([f"id_{j}", group, f"{val_a:.4f}", f"{val_b:.4f}"])

            try:
                oracle_out_raw = subprocess.check_output([oracle_path, csv_file], text=True).strip()
                oracle_out = float(oracle_out_raw)
            except Exception as e:
                # If oracle fails (e.g. due to bad random generation), we skip or fail.
                # With 100 rows, it's highly unlikely to have < 2 valid rows per group.
                continue

            try:
                agent_out_raw = subprocess.check_output([repl_path, csv_file], text=True).strip()
                agent_out = float(agent_out_raw)
            except subprocess.CalledProcessError as e:
                assert False, f"Agent executable failed on test CSV {i}: {e}"
            except ValueError:
                assert False, f"Agent executable output could not be parsed as float: '{agent_out_raw}'"

            assert math.isfinite(agent_out), f"Agent executable output must be finite, got: '{agent_out_raw}'"
            diff = abs(oracle_out - agent_out)
            max_diff = max(max_diff, diff)

    threshold = 1e-4
    assert max_diff <= threshold, f"Max absolute error {max_diff} exceeds threshold {threshold}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
