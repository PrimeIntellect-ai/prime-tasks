#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import random
import string
import socket
import tempfile
import pytest

ORACLE_PATH = "/app/oracle_processor"
REPO_PATH = "/app/backend-repo"
AGENT_PATH = "/app/backend-repo/backend_processor"
SOURCE_PATH = "/app/backend-repo/processor.c"
SECRET_PATH = "/app/backend-repo/secret.h"


def _secret_value(data):
    text = data.decode("utf-8", errors="strict")
    match = re.search(
        r"^\s*#\s*define\s+SECRET_KEY\s+(0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*\b",
        text,
        re.MULTILINE,
    )
    assert match, "SECRET_KEY definition is missing"
    return int(match.group(1), 0)


def test_backend_rebuilt_from_repaired_source_and_git_secret():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), "Oracle not executable"
    assert os.path.isfile(AGENT_PATH), f"Agent program missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), "Agent program not executable"

    with open(ORACLE_PATH, "rb") as f:
        oracle_binary = f.read()
    with open(AGENT_PATH, "rb") as f:
        submitted_binary = f.read()
    assert submitted_binary != oracle_binary, "backend_processor is a byte-identical copy of the oracle"

    assert os.path.isfile(SOURCE_PATH), "processor.c is missing"
    assert os.path.isfile(SECRET_PATH), "secret.h was not recovered"

    history = subprocess.run(
        ["git", "rev-list", "--reverse", "--all", "--", "secret.h"],
        cwd=REPO_PATH,
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    ).stdout.splitlines()
    assert history, "No Git history for secret.h was found"

    historical_secret = None
    for commit in history:
        result = subprocess.run(
            ["git", "show", f"{commit}:secret.h"],
            cwd=REPO_PATH,
            capture_output=True,
            timeout=5,
        )
        if result.returncode == 0:
            historical_secret = _secret_value(result.stdout)
            break
    assert historical_secret is not None, "Could not recover SECRET_KEY from Git history"

    with open(SECRET_PATH, "rb") as f:
        working_secret = _secret_value(f.read())
    assert working_secret == historical_secret, "secret.h does not contain the key from Git history"

    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        source_text = f.read()
    assert re.search(r'^\s*#\s*include\s*["<]secret\.h[">]', source_text, re.MULTILINE), \
        "processor.c does not include the recovered secret.h"

    # Confirm the repaired project builds from a clean output path using its Makefile.
    os.remove(AGENT_PATH)
    build = subprocess.run(
        ["make", "-B"],
        cwd=REPO_PATH,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"Clean Makefile build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(AGENT_PATH), "Makefile did not create backend_processor"
    assert os.access(AGENT_PATH, os.X_OK), "Makefile output is not executable"

    # Independently compile the repaired C source, then install that exact build at
    # the required path. This prevents a Makefile from satisfying the check by
    # copying the shipped oracle instead of compiling processor.c.
    rebuilt_path = os.path.join(REPO_PATH, ".verifier_backend_processor")
    try:
        compile_result = subprocess.run(
            ["gcc", "-o", rebuilt_path, "processor.c", "-lm"],
            cwd=REPO_PATH,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"Independent C compilation failed:\n"
            f"{compile_result.stdout}\n{compile_result.stderr}"
        )
        assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)
        os.replace(rebuilt_path, AGENT_PATH)
    finally:
        if os.path.exists(rebuilt_path):
            os.remove(rebuilt_path)


def test_fuzz_equivalence():
    """
    Fuzz-equivalence verifier:
    Generate N=1000 random binary and text streams, length 1 to 10000 bytes.
    Compare stdout of oracle and agent program.
    """
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable"
    assert os.path.isfile(AGENT_PATH), f"Agent program missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program not executable"

    random.seed(42)

    for i in range(1000):
        length = random.randint(1, 10000)
        if random.choice([True, False]):
            chars = string.ascii_letters + string.digits + string.punctuation + " \n\t"
            input_data = "".join(random.choice(chars) for _ in range(length)).encode('utf-8')
        else:
            input_data = bytes(random.getrandbits(8) for _ in range(length))

        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH],
                input=input_data,
                capture_output=True,
                timeout=2
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {i}")

        try:
            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=input_data,
                capture_output=True,
                timeout=2
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input {i}")

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on input {i} (length {length}).\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Agent output: {agent_out!r}\n"
                f"Input data snippet: {input_data[:100]!r}"
            )


def test_services_running_and_integration():
    """
    Test end-to-end flow:
    Frontend listening on TCP 8000, backend on TCP 8001.
    Send a filename with spaces to localhost:8000, get hash back.
    """
    with tempfile.NamedTemporaryFile(prefix="test file ", suffix=" with spaces.txt", delete=False) as f:
        test_filepath = f.name
        test_content = b"Hello World! This is a test file to hash.\n"
        f.write(test_content)

    try:
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=test_content,
            capture_output=True,
            timeout=2
        )
        expected_hash = oracle_proc.stdout

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        try:
            s.connect(("127.0.0.1", 8000))
        except ConnectionRefusedError:
            pytest.fail("Frontend service is not listening on 127.0.0.1:8000")

        s.sendall(f"{test_filepath}\n".encode('utf-8'))

        response = b""
        while True:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
            except socket.timeout:
                break

        s.close()

        assert response == expected_hash, (
            f"End-to-end integration failed. Expected hash {expected_hash!r}, "
            f"but got {response!r}"
        )
    finally:
        if os.path.exists(test_filepath):
            os.remove(test_filepath)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
