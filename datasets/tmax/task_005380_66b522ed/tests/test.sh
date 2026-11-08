#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/config_drift_analyzer"
AGENT_SCRIPT = "/home/user/drift_analyzer.py"
NUM_TESTS = 100
SEED = 42

def generate_random_csv(filepath):
    num_rows = random.randint(100, 5000)
    metrics = ["max_conn", "mem_limit", "timeout", "workers"]

    with open(filepath, 'w') as f:
        f.write("server_id,timestamp,metric_name,value\n")
        for _ in range(num_rows):
            sid_len = random.randint(3, 8)
            server_id = "srv-" + "".join(random.choices(string.ascii_letters + string.digits, k=sid_len))
            if random.random() < 0.05:
                server_id = ""

            timestamp = random.randint(-100, 1000000)

            metric_name = random.choice(metrics)
            if random.random() < 0.05:
                metric_name = ""

            if random.random() < 0.8:
                value = f"{random.uniform(0.0, 1000.0):.6f}"
            else:
                value = ""

            f.write(f"{server_id},{timestamp},{metric_name},{value}\n")

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"

    random.seed(SEED)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_TESTS):
            input_csv = os.path.join(tmpdir, f"input_{i}.csv")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.json")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.json")
            trace_file = os.path.join(tmpdir, f"trace_{i}.log")

            generate_random_csv(input_csv)

            oracle_cmd = [ORACLE_PATH, input_csv, oracle_out]
            res_oracle = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert res_oracle.returncode == 0, f"Oracle failed on input {input_csv}. Stderr: {res_oracle.stderr}"

            agent_cmd = [
                "/usr/bin/strace", "-f", "-qq", "-e", "trace=execve", "-o", trace_file,
                "/usr/bin/python3", AGENT_SCRIPT, input_csv, agent_out,
            ]
            res_agent = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert res_agent.returncode == 0, f"Agent script failed on input {input_csv}. Stderr: {res_agent.stderr}"

            with open(trace_file, 'r') as f:
                exec_lines = [line for line in f if "execve(" in line]
            assert len(exec_lines) == 1, (
                "Agent script delegated processing to another executable instead of implementing it; "
                f"observed execve calls: {exec_lines}"
            )

            assert os.path.exists(oracle_out), f"Oracle did not produce output file {oracle_out}"
            assert os.path.exists(agent_out), f"Agent did not produce output file {agent_out}"

            with open(oracle_out, 'r') as f:
                oracle_data = f.read()
            with open(agent_out, 'r') as f:
                agent_data = f.read()

            if oracle_data != agent_data:
                with open(input_csv, 'r') as f:
                    input_snippet = "".join(f.readlines()[:10])
                pytest.fail(
                    f"Mismatch on test iteration {i}.\n\n"
                    f"Input CSV snippet:\n{input_snippet}...\n\n"
                    f"Oracle Output (first 200 chars): {oracle_data[:200]}\n"
                    f"Agent Output (first 200 chars): {agent_data[:200]}\n\n"
                    f"Outputs must be exactly identical (bit-for-bit)."
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
