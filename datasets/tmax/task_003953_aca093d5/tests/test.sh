#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile

def test_fit_spectrum_fuzz_equivalence():
    agent_script = "/home/user/fit_spectrum.sh"
    oracle_script = "/tests/oracle_fit_spectrum"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} not found."
    assert os.access(oracle_script, os.X_OK), f"Oracle script {oracle_script} is not executable."

    random.seed(42)
    N = 500
    lines = 10000

    with tempfile.TemporaryDirectory() as tmpdir:
        input_file = os.path.join(tmpdir, "input.txt")

        for i in range(N):
            # Generate input file
            with open(input_file, "w") as f:
                for _ in range(lines):
                    val = random.uniform(0.0, 100.0)
                    f.write(f"{val:.4f}\n")

            # Run oracle
            oracle_res = subprocess.run([oracle_script, input_file], capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i} with error: {oracle_res.stderr}"
            oracle_out = oracle_res.stdout.strip()

            # Run agent
            agent_res = subprocess.run([agent_script, input_file], capture_output=True, text=True)
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i} with error: {agent_res.stderr}"
            agent_out = agent_res.stdout.strip()

            assert agent_out == oracle_out, (
                f"Mismatch on iteration {i}.\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output: {agent_out}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
