#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random


def test_query_engine_fuzz_equivalence():
    agent_bin = "/home/user/query_engine"
    oracle_bin = "/tests/reference_engine"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"

    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary is not executable: {oracle_bin}"

    random.seed(42)
    cases = [(random.randint(1, 200), random.randint(1, 200)) for _ in range(1000)]
    expected = []

    # Compute expected results before running the submission, then remove the
    # oracle so the submitted artifact cannot delegate queries to it.
    for source, target in cases:
        oracle_res = subprocess.run(
            [oracle_bin, str(source), str(target)],
            capture_output=True,
            text=True,
        )
        assert oracle_res.returncode == 0, (
            f"Oracle binary failed on input '{source} {target}'.\n"
            f"Stderr: {oracle_res.stderr}"
        )
        expected.append(oracle_res.stdout.strip())

    os.unlink(oracle_bin)
    assert not os.path.exists(oracle_bin), "Failed to remove oracle before testing submission"

    for (source, target), oracle_out in zip(cases, expected):
        agent_res = subprocess.run(
            [agent_bin, str(source), str(target)],
            capture_output=True,
            text=True,
        )
        assert agent_res.returncode == 0, (
            f"Agent binary failed on input '{source} {target}'.\n"
            f"Stderr: {agent_res.stderr}"
        )
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input '{source} {target}'.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
