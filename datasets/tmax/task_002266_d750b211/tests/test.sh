#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_audit"
    agent_path = "/home/user/audit_cli"

    assert os.path.isfile(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle not executable at {oracle_path}"

    assert os.path.isfile(agent_path), f"Agent program not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent program not executable at {agent_path}"

    random.seed(42)
    cases = []
    for _ in range(100):
        cases.append((
            random.randint(1, 1000),
            random.randint(0, 20),
            random.randint(1, 10),
        ))

    expected = []
    for start_account_id, offset, limit in cases:
        args = [str(start_account_id), str(offset), str(limit)]
        oracle_proc = subprocess.run(
            [oracle_path] + args, capture_output=True, text=True
        )
        assert oracle_proc.returncode == 0, (
            f"Oracle failed on args {args}:\n{oracle_proc.stderr}"
        )
        try:
            expected.append(json.loads(oracle_proc.stdout))
        except json.JSONDecodeError:
            pytest.fail(
                f"Oracle output is not valid JSON on args {args}:\n"
                f"{oracle_proc.stdout}"
            )

    # Do not leave the verification-only oracle available while the submission runs.
    os.remove(oracle_path)

    for (start_account_id, offset, limit), oracle_json in zip(cases, expected):
        args = [str(start_account_id), str(offset), str(limit)]
        agent_proc = subprocess.run(
            [agent_path] + args, capture_output=True, text=True
        )
        assert agent_proc.returncode == 0, (
            f"Agent program failed on args {args}:\n{agent_proc.stderr}"
        )

        try:
            agent_json = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(
                f"Agent output is not valid JSON on args {args}:\n"
                f"{agent_proc.stdout}"
            )

        assert agent_json == oracle_json, (
            f"Mismatch on args {args}.\n"
            f"Oracle output: {oracle_json}\n"
            f"Agent output: {agent_json}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
