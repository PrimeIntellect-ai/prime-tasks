#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_build_pipeline():
    pipeline_dir = "/home/user/etl_pipeline"
    assert os.path.isdir(pipeline_dir), f"Pipeline directory not found at {pipeline_dir}"

    proc = subprocess.run(["cargo", "build", "--release"], cwd=pipeline_dir, capture_output=True, text=True)
    assert proc.returncode == 0, f"cargo build --release failed:\n{proc.stderr}"

def test_fuzz_equivalence():
    oracle_path = "/app/oracle/etl_processor_oracle"
    agent_path = "/home/user/etl_pipeline/target/release/etl_processor"

    assert os.path.isfile(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary not found at {agent_path}"

    random.seed(42)
    sensors = ["S1", "Alpha", "Beta99", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota"]

    for i in range(200):
        num_lines = random.randint(500, 5000)
        lines = []
        for _ in range(num_lines):
            ts = random.randint(1600000000, 1600086400)
            sensor = random.choice(sensors)
            val = random.randint(-200, 1200)
            lines.append(f"{ts},{sensor},{val}")

        csv_data = "\n".join(lines) + "\n"

        oracle_proc = subprocess.run([oracle_path], input=csv_data.encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        agent_proc = subprocess.run([agent_path], input=csv_data.encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr.decode()}"
        assert agent_proc.returncode == 0, f"Agent failed on iteration {i}:\n{agent_proc.stderr.decode()}"

        oracle_out = oracle_proc.stdout.decode('utf-8')
        agent_out = agent_proc.stdout.decode('utf-8')

        if oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"Input preview:\n{csv_data[:200]}...\n\n"
                f"Oracle output preview:\n{oracle_out[:200]}...\n\n"
                f"Agent output preview:\n{agent_out[:200]}..."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
