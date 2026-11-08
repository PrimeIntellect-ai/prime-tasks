#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import string
import subprocess


def test_final_state():
    library_path = "/home/user/auth_lib/libauth.so"
    solve_path = "/home/user/solve.py"
    oracle_path = "/tests/oracle"

    assert os.path.isfile(library_path), "libauth.so was not compiled or is missing."
    assert os.path.isfile(solve_path), "solve.py is missing."
    assert os.path.isfile(oracle_path), "Verification oracle is missing."

    random.seed(42)
    inputs = []
    for _ in range(100):
        length = random.randint(1, 50)
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        inputs.append(token)

    input_data = '\n'.join(inputs) + '\n'

    oracle_proc = subprocess.run(
        ["python3", oracle_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"

    oracle_lines = oracle_proc.stdout.strip().split('\n')
    assert len(oracle_lines) == len(inputs), "Oracle did not output the expected number of lines."

    # Ensure libauth.so is a loadable shared library exporting the required
    # function, and verify that the library itself implements the expected logic.
    try:
        library = ctypes.CDLL(library_path)
        validate_token = library.validate_token
    except (OSError, AttributeError) as exc:
        raise AssertionError(f"libauth.so is not a valid loadable authentication library: {exc}")

    validate_token.argtypes = [ctypes.c_char_p]
    validate_token.restype = ctypes.c_int
    for token, expected in zip(inputs, oracle_lines):
        actual = validate_token(token.encode())
        assert str(actual) == expected, (
            f"libauth.so mismatch on input '{token}'. Expected: {expected}, Got: {actual}"
        )

    # The submitted bridge must not be able to delegate its work to the oracle.
    os.remove(oracle_path)

    agent_proc = subprocess.run(
        ["python3", solve_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed: {agent_proc.stderr}"

    agent_lines = agent_proc.stdout.strip().split('\n')
    assert len(agent_lines) == len(inputs), "Agent script did not output the expected number of lines."

    for i, (oracle_out, agent_out) in enumerate(zip(oracle_lines, agent_lines)):
        assert oracle_out == agent_out, (
            f"Mismatch on input '{inputs[i]}'. "
            f"Expected: {oracle_out}, Got: {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
