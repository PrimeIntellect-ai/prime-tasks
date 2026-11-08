#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess


def read_token(path):
    with open(path, "r") as f:
        return f.read().strip()


def test_task_completion():
    token_file = "/home/user/new_token.txt"
    script_file = "/home/user/rotate_token.sh"

    # 1. Check if token file exists and has correct initial content.
    assert os.path.exists(token_file), f"{token_file} does not exist. Did you execute your script to create it?"

    content = read_token(token_file)
    expected_initial_hash = hashlib.sha256(b"8082:tok_789ghi:secret_salt_2024").hexdigest()
    assert content == expected_initial_hash, (
        f"Incorrect hash in {token_file}. Expected {expected_initial_hash}, got {content}. "
        "Make sure you identified the correct log entry and formatted the string correctly."
    )

    # 2. Check script existence and executable permissions.
    assert os.path.exists(script_file), f"{script_file} does not exist."
    st = os.stat(script_file)
    assert st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"{script_file} is not executable."

    # 3. Preserve the original fixed functionality check.
    test_port = "9999"
    test_token = "tok_test123"
    expected_test_hash = hashlib.sha256(
        f"{test_port}:{test_token}:secret_salt_2024".encode()
    ).hexdigest()

    result = subprocess.run(
        [script_file, test_port, test_token],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}: {result.stderr}"
    )
    new_content = read_token(token_file)
    assert new_content == expected_test_hash, (
        f"Script did not compute the correct hash for test arguments. "
        f"Expected {expected_test_hash}, got {new_content}."
    )

    # 4. Exercise unpredictable argument pairs so fixed-output implementations fail.
    for _ in range(6):
        random_port = str(secrets.randbelow(50000) + 10000)
        random_token = "tok_" + secrets.token_hex(16)
        expected = hashlib.sha256(
            f"{random_port}:{random_token}:secret_salt_2024".encode()
        ).hexdigest()

        result = subprocess.run(
            [script_file, random_port, random_token],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, (
            f"Script rejected a valid two-argument invocation: {result.stderr}"
        )
        actual = read_token(token_file)
        assert actual == expected, (
            f"Script computed an incorrect hash for port {random_port} and a generated token. "
            f"Expected {expected}, got {actual}."
        )

    # 5. The script must reject argument counts other than exactly two.
    invalid_argument_lists = [
        [],
        ["1234"],
        ["1234", "tok_value", "extra"],
        ["1", "a", "b", "c", "d"],
    ]
    for args in invalid_argument_lists:
        result = subprocess.run(
            [script_file, *args],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode != 0, (
            f"Script accepted {len(args)} arguments, but it must accept exactly two."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
