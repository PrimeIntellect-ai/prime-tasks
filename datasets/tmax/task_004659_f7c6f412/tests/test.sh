#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import pytest


def test_query_tool_exists_and_executable():
    path = "/home/user/query_tool"
    assert os.path.isfile(path), f"Missing query tool at {path}"
    assert not os.path.islink(path), f"Query tool at {path} must be an executable script or binary, not a symlink"
    assert os.access(path, os.X_OK), f"Query tool at {path} is not executable"


def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_tool"
    agent_path = "/home/user/query_tool"

    assert os.path.isfile(oracle_path), f"Oracle tool missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent tool missing at {agent_path}"

    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Query tool must not be a byte-identical copy of the reference implementation"

    random.seed(42)
    fuzz_N = 20

    for _ in range(fuzz_N):
        F = random.randint(-5, 500)
        K = random.randint(1, 50)

        oracle_cmd = [oracle_path, str(F), str(K)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on F={F}, K={K}\nStderr: {oracle_res.stderr}"

        agent_cmd = [agent_path, str(F), str(K)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent failed on F={F}, K={K}\nStderr: {agent_res.stderr}"

        oracle_output = oracle_res.stdout.strip()
        agent_output = agent_res.stdout.strip()

        try:
            oracle_json = json.loads(oracle_output)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle output is not valid JSON on F={F}, K={K}:\n{oracle_output}")

        try:
            agent_json = json.loads(agent_output)
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON on F={F}, K={K}:\n{agent_output}")

        assert agent_json == oracle_json, (
            f"Output mismatch on F={F}, K={K}.\n"
            f"Oracle: {oracle_json}\n"
            f"Agent:  {agent_json}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
