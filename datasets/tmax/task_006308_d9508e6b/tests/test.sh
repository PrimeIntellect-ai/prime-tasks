#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import urllib.error
import urllib.parse
import urllib.request

import pytest

PROJECT = '/home/user/rust_encoder'
EXECUTABLE = PROJECT + '/target/debug/rust_encoder'


def encoded(message, shift):
    return ''.join(chr(ord(c) + shift ** 2) for c in message)


def test_rust_project_builds_cleanly():
    clean = subprocess.run(
        ['cargo', 'clean'], cwd=PROJECT, capture_output=True, text=True, timeout=120
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ['cargo', 'build'], cwd=PROJECT, capture_output=True, text=True, timeout=120
    )
    assert build.returncode == 0, f"cargo build failed:\n{build.stdout}\n{build.stderr}"


def test_rust_executable_exists():
    executable_path = '/home/user/rust_encoder/target/debug/rust_encoder'
    assert os.path.isfile(executable_path), f"The rust executable was not found at {executable_path}. Did you run 'cargo build'?"
    assert os.access(executable_path, os.X_OK), f"The file at {executable_path} is not executable."
    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The built Rust executable is not an ELF binary."


def test_rust_encoder_general_behavior():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + '_-.,' + 'éλ中🙂'
    cases = [('BorrowCheck', 0), ('Unicodeλ中', 4)]
    for _ in range(12):
        message = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 24)))
        cases.append((message, rng.randint(0, 20)))

    for message, shift in cases:
        result = subprocess.run(
            [EXECUTABLE, message, str(shift)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, (
            f"Encoder exited with {result.returncode} for {message!r}, shift={shift}: "
            f"{result.stderr}"
        )
        assert result.stdout == encoded(message, shift) + '\n', (
            f"Incorrect Rust output for {message!r}, shift={shift}: {result.stdout!r}"
        )


def test_python_server_fixed():
    server_py_path = '/home/user/server.py'
    assert os.path.isfile(server_py_path), "The server.py file is missing."

    with open(server_py_path, 'r') as f:
        content = f.read()

    assert "qs.get('shift'" in content, "The query parameter parsing bug in server.py does not appear to be fixed. It should extract 'shift' instead of 'shft'."
    compiled = subprocess.run(
        ['python3', '-m', 'py_compile', server_py_path], capture_output=True, text=True
    )
    assert compiled.returncode == 0, f"server.py is not valid Python: {compiled.stderr}"


def request_encoding(message, shift):
    query = urllib.parse.urlencode({'msg': message, 'shift': str(shift)})
    url = 'http://127.0.0.1:8080/encode?' + query
    with urllib.request.urlopen(url, timeout=2) as response:
        assert response.getcode() == 200, f"Expected HTTP 200 OK, got {response.getcode()}"
        return response.read().decode('utf-8')


def test_server_is_running_and_responds():
    try:
        url = "http://127.0.0.1:8080/encode?msg=Test&shift=1"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            assert status == 200, f"Expected HTTP 200 OK, got {status}"
            body = response.read().decode('utf-8')
            assert body == "Uftu", f"Expected 'Uftu' for msg=Test&shift=1, got '{body}'"
    except urllib.error.URLError as e:
        pytest.fail(f"The server does not appear to be running on 127.0.0.1:8080 or failed to respond: {e}")


def test_server_general_behavior():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + '&=+%?/_-.,' + 'éλ中🙂'
    for _ in range(12):
        message = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 24)))
        shift = rng.randint(1, 15)
        try:
            body = request_encoding(message, shift)
        except urllib.error.URLError as e:
            pytest.fail(f"Server request failed for {message!r}, shift={shift}: {e}")
        assert body == encoded(message, shift), (
            f"Incorrect server output for {message!r}, shift={shift}: {body!r}"
        )


def test_artifact_file_contents():
    artifact_path = '/home/user/artifact.txt'
    assert os.path.isfile(artifact_path), f"The artifact file at {artifact_path} is missing."

    with open(artifact_path, 'r') as f:
        content = f.read()

    expected_content = "Jpnw}"
    assert content == expected_content, f"The artifact file content is incorrect. Expected '{expected_content}', but got '{content}'."

    try:
        live_body = request_encoding('Agent', 3)
    except urllib.error.URLError as e:
        pytest.fail(f"Could not compare artifact with the server's raw response: {e}")
    assert content == live_body, (
        f"artifact.txt is not exactly the current raw server response: "
        f"artifact={content!r}, response={live_body!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
