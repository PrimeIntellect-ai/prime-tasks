#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pandas:pandas"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import time
import subprocess
import pandas as pd
import pytest


def test_fast_etl_performance_and_accuracy():
    script_path = "/home/user/fast_etl.sh"
    output_path = "/home/user/top_sources.txt"
    raw_data_path = "/home/user/data/raw_edges.csv"

    assert os.path.isfile(script_path), f"Missing script at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"

    # Install a fresh, equivalent 500,000-edge challenge so the input cannot have
    # been simplified before verification.
    rng = random.Random()
    rng.seed(os.urandom(32))
    challenge_path = raw_data_path + ".verifier_tmp"
    with open(challenge_path, "w") as f:
        for _ in range(500000):
            src = f"192.168.1.{rng.randint(1, 250)}"
            dst = f"10.0.0.{rng.randint(1, 250)}"
            ts = 1600000000 + rng.randint(0, 100000)
            b = rng.randint(10, 5000)
            f.write(f"{src},{dst},{ts},{b}\n")
    os.replace(challenge_path, raw_data_path)

    # Compute golden truth before running the submitted script. The expected
    # result remains in verifier memory even if the script modifies the input.
    df = pd.read_csv(raw_data_path, names=['source_ip', 'destination_ip', 'timestamp', 'bytes_transferred'])

    # 1. Filter out bytes < 100
    df = df[df['bytes_transferred'] >= 100]

    # 2. Sort by source_ip and timestamp (ascending)
    df = df.sort_values(by=['source_ip', 'timestamp'], ascending=[True, True])

    # 3. Keep exactly the 10 most recent per source_ip
    df = df.groupby('source_ip').tail(10)

    # 4. Compute score
    df['score'] = (df['bytes_transferred'] % 1000) * 1.5

    # 5. Aggregate
    agg = df.groupby('source_ip')['score'].sum().reset_index()

    # Sort descending by score to get top 25
    golden_top_25 = agg.sort_values(by=['score', 'source_ip'], ascending=[False, True]).head(25)

    # Remove output if it exists to ensure we measure the new run
    if os.path.exists(output_path):
        os.remove(output_path)

    # Run the script and measure wall-clock time
    start_time = time.time()
    result = subprocess.run([script_path], capture_output=True, text=True)
    end_time = time.time()

    assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"

    runtime = end_time - start_time
    assert runtime <= 2.0, f"Runtime {runtime:.2f}s exceeded the stringent threshold of 2.0s"

    assert os.path.isfile(output_path), f"Output file {output_path} was not created"

    # Read student output
    try:
        student_output = pd.read_csv(output_path, names=['source_ip', 'score'])
    except Exception as e:
        pytest.fail(f"Could not parse {output_path} as CSV: {e}")

    assert len(student_output) == 25, f"Expected exactly 25 lines in output, got {len(student_output)}"

    # Compare correctness
    golden_scores = golden_top_25['score'].tolist()
    student_scores = student_output['score'].tolist()

    # Check if the scores match (allowing for minor float formatting differences)
    for i, (g_score, s_score) in enumerate(zip(golden_scores, student_scores)):
        assert abs(g_score - s_score) < 1e-5, f"Rank {i+1} score mismatch: expected {g_score}, got {s_score}"

    # Check if the IPs match the expected top IPs (checking the set to avoid strict tie-breaking order issues)
    golden_ips = set(golden_top_25['source_ip'])
    student_ips = set(student_output['source_ip'])

    missing_ips = golden_ips - student_ips
    assert not missing_ips, f"Student output is missing expected top IPs: {missing_ips}"

    # Also verify that the scores associated with the IPs in the student output are correct
    golden_dict = dict(zip(agg['source_ip'], agg['score']))
    for _, row in student_output.iterrows():
        ip = row['source_ip']
        score = row['score']
        expected_score = golden_dict.get(ip)
        assert expected_score is not None, f"IP {ip} not found in valid aggregated results"
        assert abs(expected_score - score) < 1e-5, f"Incorrect score for IP {ip}: expected {expected_score}, got {score}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
