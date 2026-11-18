#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_fuzz_equivalence():
    oracle_path = '/tests/oracle.py'
    agent_path = '/home/user/adaptive_integrator.sh'

    assert os.path.isfile(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing: {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent script not executable: {agent_path}"

    N = 200
    random.seed(42)

    for i in range(N):
        y0 = random.uniform(0.0, 5.0)
        t_end = random.uniform(1.0, 10.0)
        h0 = random.uniform(0.01, 0.1)

        args = [f"{y0:.6f}", f"{t_end:.6f}", f"{h0:.6f}"]

        oracle_cmd = ['python3', oracle_path] + args
        agent_cmd = [agent_path] + args

        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on inputs {args}:\n{oracle_proc.stderr}"

        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed on inputs {args}:\n{agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on inputs y0={args[0]}, t_end={args[1]}, h0={args[2]}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Actual (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
