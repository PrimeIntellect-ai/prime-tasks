#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import tempfile
import numpy as np
import pytest

def generate_matrix(size, rank_deficient=False, rng=None):
    if rng is None:
        rng = np.random.default_rng()

    if rank_deficient:
        rank = max(1, size // 2)
        A = rng.normal(size=(size, rank))
        B = rng.normal(size=(rank, size))
        M = A @ B
    else:
        M = rng.normal(size=(size, size))
    return M

def test_matrix_prep_fuzz_equivalence():
    agent_script = "/home/user/matrix_prep.py"
    oracle_script = "/tests/oracle_matrix_prep.py"

    assert os.path.exists(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} is missing."

    rng = np.random.default_rng(seed=42)

    N = 1000
    with tempfile.TemporaryDirectory() as tmpdir:
        input_csv = os.path.join(tmpdir, "input.csv")

        for i in range(N):
            size = rng.integers(5, 51)
            is_rank_deficient = rng.random() < 0.3

            M = generate_matrix(size, rank_deficient=is_rank_deficient, rng=rng)
            np.savetxt(input_csv, M, delimiter=',')

            oracle_proc = subprocess.run(
                [sys.executable, oracle_script, input_csv],
                capture_output=True, text=True
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}."

            agent_proc = subprocess.run(
                [sys.executable, agent_script, input_csv],
                capture_output=True, text=True
            )

            if agent_proc.returncode != 0:
                pytest.fail(f"Agent script failed on iteration {i} (size={size}, rank_deficient={is_rank_deficient}).\nStderr: {agent_proc.stderr}")

            try:
                oracle_out = np.loadtxt(oracle_proc.stdout.splitlines(), delimiter=',')
                agent_out = np.loadtxt(agent_proc.stdout.splitlines(), delimiter=',')
            except Exception as e:
                pytest.fail(f"Failed to parse CSV output on iteration {i}. Error: {e}\nAgent output:\n{agent_proc.stdout}")

            if not np.allclose(oracle_out, agent_out, atol=1e-4, rtol=1e-4):
                pytest.fail(f"Output mismatch on iteration {i} (size={size}, rank_deficient={is_rank_deficient}).\nInput matrix:\n{M}\nOracle output:\n{oracle_out}\nAgent output:\n{agent_out}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
