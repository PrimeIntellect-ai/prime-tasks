#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import tempfile
import numpy as np


def test_bc_installed_and_scale_fixed():
    """Test that bc is compiled, installed to the correct path, and defaults to scale=20."""
    bc_path = "/home/user/bin/bc"
    assert os.path.isfile(bc_path), f"Compiled bc not found at {bc_path}"
    assert os.access(bc_path, os.X_OK), f"{bc_path} is not executable"

    result = subprocess.run(
        f'echo "5/2" | {bc_path}',
        shell=True,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Running bc failed: {result.stderr}"
    output = result.stdout.strip()
    expected = "2.50000000000000000000"
    assert output == expected, f"Expected bc to output {expected}, got '{output}'. The scale perturbation was not correctly fixed."


def test_process_embeddings_fuzz_equivalence():
    """Fuzz test the bash pipeline against the python oracle."""
    agent_script = "/home/user/process_embeddings.sh"
    oracle_script = "/tests/process_embeddings_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    np.random.seed(42)
    cases = []

    try:
        # Generate every expected result before running the submission. The oracle
        # is then removed so the submitted script cannot delegate to it.
        for i in range(50):
            N = random.randint(3, 10)
            M = random.randint(2, 5)
            rows = random.randint(10, 100)

            dataset = np.round(np.random.uniform(-10.0, 10.0, (rows, N)), 4)
            matrix = np.round(np.random.uniform(-10.0, 10.0, (N, M)), 4)
            query = np.round(np.random.uniform(-10.0, 10.0, N), 4)

            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.csv') as d_file, \
                 tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.csv') as m_file:
                np.savetxt(d_file, dataset, delimiter=',', fmt='%.4f')
                np.savetxt(m_file, matrix, delimiter=',', fmt='%.4f')
                d_path = d_file.name
                m_path = m_file.name

            query_str = ','.join(f"{x:.4f}" for x in query)
            oracle_cmd = ["python3", oracle_script, d_path, m_path, query_str]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}: {oracle_res.stderr}"
            cases.append((i, N, M, rows, d_path, m_path, query_str, oracle_res.stdout.strip()))

        os.remove(oracle_script)
        assert not os.path.exists(oracle_script), "Oracle could not be removed before submission execution"

        for i, N, M, rows, d_path, m_path, query_str, oracle_out in cases:
            agent_cmd = ["/bin/bash", agent_script, d_path, m_path, query_str]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i}: {agent_res.stderr}"
            agent_out = agent_res.stdout.strip()

            assert agent_out == oracle_out, (
                f"Mismatch on iteration {i}.\n"
                f"N={N}, M={M}, rows={rows}\n"
                f"Query: {query_str}\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output: '{agent_out}'"
            )
    finally:
        for case in cases:
            for path in (case[4], case[5]):
                if os.path.exists(path):
                    os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
