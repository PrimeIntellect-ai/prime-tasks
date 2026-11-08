#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest


def generate_test_case():
    N = random.randint(10, 500)
    max_e = N * (N - 1) // 2
    E = random.randint(10, min(2000, max_e)) if N > 1 else 0

    edges = set()
    while len(edges) < E:
        u = random.randint(0, N - 1)
        v = random.randint(0, N - 1)
        if u != v:
            if u > v:
                u, v = v, u
            edges.add((u, v))

    lines = [f"{N} {E}"]
    for u, v in edges:
        w = random.randint(1, 10000)
        lines.append(f"{u} {v} {w}")

    Q = random.randint(1, 100)
    lines.append(f"{Q}")
    for _ in range(Q):
        u = random.randint(0, N - 1)
        v = random.randint(0, N - 1)
        lines.append(f"{u} {v}")

    return "\n".join(lines) + "\n"


def test_base_graph_exists_and_format():
    base_graph_path = "/home/user/base_graph.txt"
    assert os.path.exists(base_graph_path), f"Phase 1 output missing: {base_graph_path} does not exist."
    assert os.path.isfile(base_graph_path), f"{base_graph_path} is not a regular file."

    with open(base_graph_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) > 0, f"{base_graph_path} is empty."
    for line in lines:
        parts = line.split()
        assert len(parts) == 4, f"Invalid format in {base_graph_path}: '{line}' does not have 4 parts."
        assert parts[0] == "LINK", f"Invalid format in {base_graph_path}: '{line}' does not start with LINK."
        try:
            int(parts[1])
            int(parts[2])
            int(parts[3])
        except ValueError:
            pytest.fail(f"Invalid format in {base_graph_path}: '{line}' contains non-integer node/capacity values.")

    expected_lines = [
        "LINK 0 1 500",
        "LINK 1 2 300",
        "LINK 2 3 400",
        "LINK 3 0 200",
    ]
    assert lines == expected_lines, "base_graph.txt does not match the complete topology shown in the video."


def test_backup_router_fuzz_equivalence():
    agent_exec = "/home/user/backup_router"
    oracle_exec = "/tests/backup_router_oracle"

    assert os.path.exists(agent_exec), f"Agent executable missing at {agent_exec}"
    assert os.path.isfile(agent_exec), f"Agent file at {agent_exec} is not a regular file"
    assert os.access(agent_exec, os.X_OK), f"Agent file at {agent_exec} is not executable"

    assert os.path.exists(oracle_exec), f"Oracle executable missing at {oracle_exec}"
    assert os.access(oracle_exec, os.X_OK), f"Oracle file at {oracle_exec} is not executable"

    random.seed(42)
    NUM_ITERATIONS = 100

    for i in range(NUM_ITERATIONS):
        test_input = generate_test_case()

        try:
            agent_proc = subprocess.run(
                [agent_exec],
                input=test_input,
                text=True,
                capture_output=True,
                timeout=5
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on iteration {i+1}.")

        try:
            oracle_proc = subprocess.run(
                [oracle_exec],
                input=test_input,
                text=True,
                capture_output=True,
                timeout=5
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle program timed out on iteration {i+1}. This indicates a test environment issue.")

        assert agent_proc.returncode == 0, f"Agent program crashed (return code {agent_proc.returncode}) on iteration {i+1}."

        if agent_out != oracle_out:
            fail_msg = (
                f"Mismatch on iteration {i+1}.\n"
                f"Input:\n{test_input[:200]}... (truncated)\n"
                f"Expected Output (Oracle):\n{oracle_out[:200]}...\n"
                f"Actual Output (Agent):\n{agent_out[:200]}..."
            )
            pytest.fail(fail_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
