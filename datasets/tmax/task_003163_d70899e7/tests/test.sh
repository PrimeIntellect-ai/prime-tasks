#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import tempfile
import random
import numpy as np
import h5py

def test_solver_fuzz_equivalence():
    agent_script = '/home/user/solver.py'
    oracle_script = '/tests/solver_oracle.py'

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} not found."

    np.random.seed(42)
    random.seed(42)

    N = 50
    for i in range(N):
        mean_val = random.uniform(-1000.0, 1000.0)
        data = np.random.normal(loc=mean_val, scale=10.0, size=10000)

        with tempfile.NamedTemporaryFile(suffix='.h5', delete=False) as tmp:
            tmp_path = tmp.name

        try:
            with h5py.File(tmp_path, 'w') as f:
                f.create_dataset('/data/signal', data=data, dtype='float64')

            # Run oracle uploaded only at verification time.
            oracle_cmd = [sys.executable, oracle_script, tmp_path]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed to run on test input: {oracle_res.stderr}"
            oracle_output = oracle_res.stdout.strip()

            # Run agent.
            agent_cmd = [sys.executable, agent_script, tmp_path]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert agent_res.returncode == 0, f"Agent script failed on test input: {agent_res.stderr}"
            agent_output = agent_res.stdout.strip()

            assert agent_output == oracle_output, (
                f"Output mismatch on fuzz input {i} (data mean approx {mean_val:.2f}).\n"
                f"Expected (Oracle): {oracle_output}\n"
                f"Got (Agent): {agent_output}"
            )
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
