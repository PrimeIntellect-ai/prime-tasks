#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import pytest


def test_required_go_test_exists_and_runs():
    test_path = "/home/user/hasher_test.go"
    assert os.path.isfile(test_path), f"Required Go test missing at {test_path}"

    proc = subprocess.run(
        ["go", "test", "-json", "-count=1", "."],
        cwd="/home/user",
        capture_output=True,
        text=True,
        env={**os.environ, "GO111MODULE": "off"},
        timeout=60,
    )
    assert proc.returncode == 0, f"Go tests failed.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"

    events = []
    for line in proc.stdout.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    assert any(e.get("Action") == "pass" and e.get("Test") for e in events), \
        "hasher_test.go did not execute any passing Go test function"


def test_build_hasher_fuzz_equivalence():
    agent_path = "/home/user/build_hasher"
    oracle_path = "/tests/oracle_hasher"

    assert os.path.exists(agent_path), f"Agent executable missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent executable at {agent_path} is not executable"

    assert os.path.exists(oracle_path), f"Oracle executable missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle executable at {oracle_path} is not executable"

    # Set up fixed seed for reproducibility
    rng = random.Random(42)

    N = 500

    for i in range(N):
        # Generate random length between 0 and 500,000
        length = rng.randint(0, 500_000)

        # Generate random bytes
        if length > 0:
            # generating large random byte strings efficiently
            # random.randbytes is available in Python 3.9+
            fuzz_input = rng.randbytes(length)
        else:
            fuzz_input = b""

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=fuzz_input,
                capture_output=True,
                check=True,
                timeout=5
            )
            oracle_out = oracle_proc.stdout.decode('utf-8', errors='replace')
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on run {i} with length {length}. Stderr: {e.stderr.decode('utf-8', errors='replace')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on run {i} with length {length}.")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [agent_path],
                input=fuzz_input,
                capture_output=True,
                check=True,
                timeout=5
            )
            agent_out = agent_proc.stdout.decode('utf-8', errors='replace')
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent failed on run {i} with length {length}. Stderr: {e.stderr.decode('utf-8', errors='replace')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on run {i} with length {length}.")

        # Compare outputs
        if oracle_out != agent_out:
            # Truncate input for display if it's too long
            display_input = fuzz_input[:100].hex() + ("..." if len(fuzz_input) > 100 else "")
            pytest.fail(
                f"Mismatch on run {i} (input length {length}).\n"
                f"Input (hex, truncated): {display_input}\n"
                f"Expected (Oracle): {repr(oracle_out)}\n"
                f"Got (Agent): {repr(agent_out)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
