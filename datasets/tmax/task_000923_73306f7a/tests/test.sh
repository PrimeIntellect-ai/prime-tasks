#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def generate_input(seed):
    random.seed(seed)
    N = 10
    E = 15
    lines = []
    lines.append(str(N))
    lines.append(str(E))

    edges = set()
    while len(edges) < E:
        u = random.randint(0, N-1)
        v = random.randint(0, N-1)
        if u != v and (u, v) not in edges and (v, u) not in edges:
            edges.add((u, v))

    for u, v in edges:
        lines.append(f"{u} {v}")

    lines.append("---")

    for _ in range(20):
        beta = random.uniform(0.1, 2.0)
        gamma = random.uniform(0.1, 2.0)
        lines.append(f"{beta:.4f} {gamma:.4f}")

    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/sim_mcmc.py"
    oracle_script = "/tests/oracle_bin.py"

    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script missing at {oracle_script}"

    for i in range(100):
        inp = generate_input(i)

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=inp,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script execution failed on input seed {i}:\nSTDERR:\n{agent_proc.stderr}"

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=inp,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle script execution failed on input seed {i}:\nSTDERR:\n{oracle_proc.stderr}"

        agent_out = agent_proc.stdout.strip()
        oracle_out = oracle_proc.stdout.strip()

        if agent_out != oracle_out:
            pytest.fail(
                f"Output mismatch on random seed {i}.\n"
                f"--- Input ---\n{inp}\n"
                f"--- Expected (Oracle) ---\n{oracle_out}\n"
                f"--- Actual (Agent) ---\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
