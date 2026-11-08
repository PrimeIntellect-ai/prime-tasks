#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile
import pytest

APP_DIR = "/home/user/app"
CALC_CPP = os.path.join(APP_DIR, "calc.cpp")
CALC_BIN = os.path.join(APP_DIR, "calc")
TOKEN_FILE = "/home/user/recovered_token.txt"
OUTPUT_FILE = "/home/user/output.txt"
EXPECTED_TOKEN = "super_secret_production_key_9921"
EXPECTED_OUTPUT = "3361.00000"


def run_calc(binary, token):
    result = subprocess.run(
        [binary, token],
        cwd=APP_DIR,
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{binary} failed for a valid token with exit code {result.returncode}. "
        f"stderr: {result.stderr!r}"
    )
    assert result.stderr == "", f"{binary} unexpectedly wrote to stderr: {result.stderr!r}"
    return result.stdout


def expected_stdout(token):
    return f"{sum(ord(c) for c in token) + 1.0:.5f}\n"


def test_recovered_token_file():
    token_file = TOKEN_FILE
    assert os.path.isfile(token_file), f"File {token_file} does not exist."

    with open(token_file, 'r') as f:
        content = f.read().strip()

    expected_token = EXPECTED_TOKEN
    assert content == expected_token, f"Recovered token is incorrect. Expected '{expected_token}', got '{content}'."


def test_calc_cpp_fixed():
    calc_cpp_path = CALC_CPP
    assert os.path.isfile(calc_cpp_path), f"File {calc_cpp_path} does not exist."

    with open(calc_cpp_path, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "double accumulator" in content, "calc.cpp does not seem to have 'double accumulator'. The precision loss bug might not be fixed correctly."
    assert "float accumulator" not in content, "calc.cpp still contains 'float accumulator'. The precision loss bug is not fixed."


def test_output_file():
    output_file = OUTPUT_FILE
    assert os.path.isfile(output_file), f"File {output_file} does not exist."

    with open(output_file, 'r') as f:
        content = f.read().strip()

    expected_output = EXPECTED_OUTPUT
    assert content == expected_output, f"Output is incorrect. Expected '{expected_output}', got '{content}'."


def test_compiled_artifact_and_execution():
    assert os.path.isfile(CALC_BIN), f"Compiled artifact {CALC_BIN} does not exist."
    assert os.access(CALC_BIN, os.X_OK), f"Compiled artifact {CALC_BIN} is not executable."
    with open(CALC_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{CALC_BIN} is not an ELF executable."

    # Independently build the submitted source so comments or an unrelated binary
    # cannot conceal an unfixed calculation.
    fd, rebuilt = tempfile.mkstemp(prefix="verifier_calc_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        build = subprocess.run(
            ["g++", "-O2", "calc.cpp", "-o", rebuilt],
            cwd=APP_DIR,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert build.returncode == 0, f"calc.cpp does not compile: {build.stderr}"

        dynamic_token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(10))
        tokens = [EXPECTED_TOKEN, "A", "Az09", dynamic_token]
        for token in tokens:
            expected = expected_stdout(token)
            assert run_calc(rebuilt, token) == expected, "Recompiled calc.cpp produced an incorrect result."
            assert run_calc(CALC_BIN, token) == expected, "The submitted ./calc artifact produced an incorrect result."

        production_stdout = run_calc(CALC_BIN, EXPECTED_TOKEN)
        with open(OUTPUT_FILE, "r") as f:
            saved_output = f.read().strip()
        assert saved_output == production_stdout.strip(), (
            "output.txt is not the standard output produced by the submitted ./calc binary "
            "using the recovered token."
        )
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
