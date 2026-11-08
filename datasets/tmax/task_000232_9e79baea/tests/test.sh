#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/app/auth_oracle"
AGENT_PATH = "/home/user/hash_generator"


def test_redacted_session_file():
    """Verify the redacted session ID was saved correctly."""
    filepath = "/home/user/redacted_session.txt"
    assert os.path.exists(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read()

    expected_content = "root********\n"
    assert content == expected_content, f"Content of {filepath} is incorrect. Expected {repr(expected_content)}, got {repr(content)}"


def test_hash_generator_exists_and_executable():
    """Verify the hash generator exists, is a regular file, and is executable."""
    assert os.path.exists(AGENT_PATH), f"Hash generator {AGENT_PATH} does not exist."
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a regular file."
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable."


def test_hash_generator_is_not_oracle_copy():
    """Reject a byte-identical copy of the supplied oracle."""
    assert os.path.exists(ORACLE_PATH), f"Oracle {ORACLE_PATH} missing."
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "hash_generator must be an independent implementation, not a copy of auth_oracle."


def test_fuzz_equivalence_hash_generator_without_oracle_available():
    """Fuzz the generator after removing the oracle so wrappers cannot pass."""
    assert os.path.exists(ORACLE_PATH), f"Oracle {ORACLE_PATH} missing."
    assert os.path.exists(AGENT_PATH), f"Agent executable {AGENT_PATH} missing."

    random.seed(42)
    charset = string.ascii_letters + string.digits + "_-"
    test_inputs = [
        "".join(random.choice(charset) for _ in range(random.randint(8, 64)))
        for _ in range(1000)
    ]

    expected_outputs = []
    for test_input in test_inputs:
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, test_input],
                capture_output=True,
                text=True,
                timeout=2,
                check=True,
            )
            expected_outputs.append(oracle_proc.stdout.strip())
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {repr(test_input)}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {repr(test_input)}")

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    oracle_mode = os.stat(ORACLE_PATH).st_mode & 0o7777

    # Remove the required oracle path for the entire period in which the agent
    # implementation is executed. The bytes are retained only in this verifier
    # process and restored afterward for container consistency.
    os.unlink(ORACLE_PATH)
    try:
        for i, (test_input, oracle_output) in enumerate(zip(test_inputs, expected_outputs)):
            try:
                agent_proc = subprocess.run(
                    [AGENT_PATH, test_input],
                    capture_output=True,
                    text=True,
                    timeout=2,
                )
                agent_output = agent_proc.stdout.strip()
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent timed out on input {repr(test_input)}")

            assert agent_proc.returncode == 0, f"Agent failed on input {repr(test_input)} with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}"
            assert agent_output == oracle_output, (
                f"Output mismatch on iteration {i+1}.\n"
                f"Input: {repr(test_input)}\n"
                f"Oracle output: {repr(oracle_output)}\n"
                f"Agent output:  {repr(agent_output)}"
            )
    finally:
        with open(ORACLE_PATH, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(ORACLE_PATH, oracle_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
