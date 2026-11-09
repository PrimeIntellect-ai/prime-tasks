#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import io
import os
import random
import string
import subprocess
import pytest

def generate_random_unicode_string(length):
    pool = (
        list(string.ascii_letters + string.digits + " ,.\n\t") +
        [chr(i) for i in range(0x1F600, 0x1F650)] +
        [chr(i) for i in range(0x0300, 0x0370)] +
        [chr(i) for i in range(0x4E00, 0x4E50)]
    )
    return "".join(random.choice(pool) for _ in range(length))

def generate_csv_input(num_rows=500):
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["id", "timestamp", "lang", "raw_text", "score"])

    timestamp = 1600000000
    for i in range(1, num_rows + 1):
        timestamp += random.randint(1, 100)
        lang = random.choice(["en", "fr", "es", "zh", "", "", ""])
        raw_text = generate_random_unicode_string(random.randint(10, 100))

        if random.random() < 0.3:
            score = ""
        else:
            score = f"{random.uniform(0.0, 100.0):.4f}"

        writer.writerow([i, timestamp, lang, raw_text, score])

    return output.getvalue().encode("utf-8")

def test_go_nlp_utils_fixed():
    """Verify that the vendored package compiles successfully."""
    pkg_dir = "/app/go-nlp-utils"
    assert os.path.isdir(pkg_dir), f"Directory {pkg_dir} does not exist."

    result = subprocess.run(
        ["go", "build"],
        cwd=pkg_dir,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"go build failed in {pkg_dir}:\n{result.stderr}"

def test_fuzz_equivalence():
    """Fuzz test the compiled ETL binary against the oracle."""
    oracle_path = "/tests/etl_oracle"
    agent_path = "/home/user/etl"

    assert os.path.isfile(oracle_path), f"Oracle binary {oracle_path} missing."
    assert os.path.isfile(agent_path), f"Agent binary {agent_path} missing. Did you compile it?"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable."

    random.seed(42)

    for i in range(100):
        csv_data = generate_csv_input(500)

        oracle_proc = subprocess.run([oracle_path], input=csv_data, capture_output=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr.decode('utf-8', errors='replace')}"

        agent_proc = subprocess.run([agent_path], input=csv_data, capture_output=True)

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent binary failed on iteration {i} with return code {agent_proc.returncode}\n"
                f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )

        if oracle_proc.stdout != agent_proc.stdout:
            debug_input_path = "/tmp/failed_input.csv"
            with open(debug_input_path, "wb") as f:
                f.write(csv_data)

            oracle_out = oracle_proc.stdout.decode("utf-8", errors="replace")
            agent_out = agent_proc.stdout.decode("utf-8", errors="replace")
            oracle_lines = oracle_out.splitlines()
            agent_lines = agent_out.splitlines()

            diff_msg = ""
            for line_idx, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
                if o_line != a_line:
                    diff_msg = f"First mismatch at line {line_idx + 1}:\nExpected (Oracle): {o_line}\nGot (Agent):      {a_line}"
                    break

            if not diff_msg:
                diff_msg = f"Output length mismatch. Oracle: {len(oracle_lines)} lines, Agent: {len(agent_lines)} lines."

            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"{diff_msg}\n"
                f"Input saved to {debug_input_path} for debugging."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
