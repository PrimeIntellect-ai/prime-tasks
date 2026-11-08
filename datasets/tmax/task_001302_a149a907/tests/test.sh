#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import random
import subprocess
import pytest


def generate_fuzz_input(seed):
    rng = random.Random(seed)
    N = rng.randint(10, 40)
    max_edges = max(N, N * (N - 1) // 4)
    E = rng.randint(N, max_edges)

    all_possible_edges = []
    for u in range(N):
        for v in range(u + 1, N):
            all_possible_edges.append((u, v))

    edges = rng.sample(all_possible_edges, E)
    sim_seed = rng.randint(0, 99999)

    lines = [f"{sim_seed}", f"{N} {E}"]
    for u, v in edges:
        lines.append(f"{u} {v}")

    return "\n".join(lines) + "\n"


def test_simulator_fixed():
    path = "/app/GraphSpecSim-1.0.0/graphspecsim/simulator.py"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "np.random.normal(" in content, "The typo 'np.random.norm' was not fixed to 'np.random.normal'."
    assert "np.random.norm(" not in content, "The typo 'np.random.norm' is still present."


def test_graphspecsim_installed():
    try:
        import graphspecsim
    except ImportError:
        pytest.fail("graphspecsim is not installed in the Python environment.")


def test_pipeline_fuzz_equivalence():
    oracle_path = "/tests/oracle_pipeline.py"
    agent_path = "/home/user/pipeline.py"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"

    num_tests = 500
    for i in range(num_tests):
        input_data = generate_fuzz_input(1337 + i)

        oracle_proc = subprocess.run(
            [sys.executable, oracle_path],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i}. Stderr: {oracle_proc.stderr}"

        agent_proc = subprocess.run(
            [sys.executable, agent_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on test {i}.\nInput:\n{input_data}\nStderr: {agent_proc.stderr}")

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on test {i}.\n"
                f"Input:\n{input_data}\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output: '{agent_out}'"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
