#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import random
from unittest.mock import patch
import pytest

def test_cred_rotator_fixed():
    """
    Test that cred-rotator's rotate_credentials passes the master_key via env var
    and not via command-line arguments, and that key generation succeeds.
    """
    pkg_path = "/app/cred-rotator"
    assert os.path.isdir(pkg_path), f"Package directory {pkg_path} missing."

    if pkg_path not in sys.path:
        sys.path.insert(0, pkg_path)

    try:
        from rotator.cli import rotate_credentials
    except ImportError as e:
        pytest.fail(f"Failed to import rotator.cli.rotate_credentials: {e}")

    original_run = subprocess.run
    called_args = []
    called_kwargs = []
    completed_processes = []

    def mock_run(*args, **kwargs):
        called_args.append(args)
        called_kwargs.append(kwargs)
        completed = original_run(*args, **kwargs)
        completed_processes.append(completed)
        return completed

    secret = "secret_test_key_123_fuzz"

    with patch('subprocess.run', side_effect=mock_run):
        try:
            result = rotate_credentials(master_key=secret)
        except Exception as e:
            pytest.fail(f"rotate_credentials raised an exception: {e}")

    assert called_args, "subprocess.run was never called."

    # Verify secret is NOT in the arguments
    for args_tuple in called_args:
        for arg in args_tuple:
            if isinstance(arg, list):
                assert secret not in arg, "Vulnerability remains: master_key found in subprocess arguments list!"
            elif isinstance(arg, str):
                assert secret not in arg, "Vulnerability remains: master_key found in subprocess argument string!"

    # Verify secret IS in the environment
    env_found = False
    for kwargs in called_kwargs:
        env = kwargs.get('env')
        if env and env.get('ROTATOR_MASTER_KEY') == secret:
            env_found = True
            break

    assert env_found, "ROTATOR_MASTER_KEY environment variable not passed to subprocess.run."
    assert result, "rotate_credentials returned an empty or falsy result, indicating the script failed to process the key."
    assert completed_processes, "No subprocess execution result was captured."
    assert all(proc.returncode == 0 for proc in completed_processes), (
        "Key-generation subprocess exited unsuccessfully."
    )
    expected = f"rotated_key_based_on_{secret}"
    assert result == expected, (
        f"rotate_credentials returned incorrect key output: expected {expected!r}, got {result!r}"
    )

def test_token_generator_fuzz_equivalence():
    """
    Test that the agent's token generator is bit-exact equivalent to the oracle
    on 1000 random valid inputs.
    """
    agent_script = "/home/user/token_generator.py"
    oracle_bin = "/opt/oracles/token_oracle"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."
    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} not found."

    with open(agent_script, "rb") as agent_file, open(oracle_bin, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent submission must not be a byte-identical copy of the oracle."

    random.seed(1337)

    for _ in range(1000):
        session_id = "".join(random.choices("0123456789abcdef", k=16))
        client_ip = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"

        oracle_proc = subprocess.run([oracle_bin, session_id, client_ip], capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on {session_id} {client_ip}"
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(["python3", agent_script, session_id, client_ip], capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed or crashed on input: {session_id} {client_ip}\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Fuzz equivalence mismatch!\n"
            f"Input session_id: {session_id}\n"
            f"Input client_ip:  {client_ip}\n"
            f"Oracle output:    {oracle_out}\n"
            f"Agent output:     {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
