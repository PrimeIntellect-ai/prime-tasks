#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import stat
import subprocess
import sys
import uuid

import pytest


def test_audit_py_exists():
    script_path = "/home/user/audit.py"
    assert os.path.exists(script_path), f"File {script_path} is missing."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."


def test_vulnerable_tokens_exists_and_permissions():
    output_file = "/home/user/vulnerable_tokens.json"
    assert os.path.exists(output_file), f"File {output_file} is missing."
    assert os.path.isfile(output_file), f"Path {output_file} is not a file."

    file_stat = os.stat(output_file)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o400, f"Permissions of {output_file} are {oct(permissions)}, expected 0o400."


def test_vulnerable_tokens_content():
    output_file = "/home/user/vulnerable_tokens.json"
    assert os.path.exists(output_file), f"File {output_file} is missing."

    with open(output_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Content of {output_file} is not valid JSON.")

    expected_tokens = [
        "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbiIsImlhdCI6MTYxNjIzOTAyMn0.",
        "eyJhbGciOiJOb25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJyb290IiwiaWF0IjoxNjE2MjM5MDIyfQ."
    ]

    assert isinstance(data, list), f"Expected a JSON array in {output_file}, but got {type(data).__name__}."
    assert data == expected_tokens, f"Content of {output_file} does not match the expected vulnerable tokens."


def _b64url_json(value):
    raw = json.dumps(value, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def test_audit_script_processes_log_dynamically():
    script_path = "/home/user/audit.py"
    log_path = "/home/user/jwt_logs.txt"
    output_path = "/home/user/vulnerable_tokens.json"

    nonce = uuid.uuid4().hex
    algorithms = ["HS256", "NONE", "RS256", "NoNe", "none-ish", "none"]
    tokens = []
    expected = []
    for index, algorithm in enumerate(algorithms):
        header = _b64url_json({"typ": "JWT", "marker": nonce, "alg": algorithm})
        payload = _b64url_json({"case": index, "nonce": nonce})
        token = f"{header}.{payload}.sig-{nonce}-{index}"
        tokens.append(token)
        if algorithm.lower() == "none":
            expected.append(token)

    original_log = open(log_path, "rb").read()
    original_output = open(output_path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(output_path).st_mode)

    try:
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("\n".join(tokens) + "\n")
        os.remove(output_path)

        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Running {script_path} failed with exit code {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(output_path), "The audit script did not create vulnerable_tokens.json."

        try:
            with open(output_path, "r", encoding="utf-8") as f:
                actual = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The audit script produced invalid JSON: {exc}")

        assert isinstance(actual, list), "The audit script output must be a JSON array."
        assert actual == expected, (
            "The audit script did not decode the current log headers and select exactly "
            "the tokens whose alg value is case-insensitively equal to 'none'."
        )
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        if os.path.lexists(output_path):
            os.remove(output_path)
        with open(output_path, "wb") as f:
            f.write(original_output)
        os.chmod(output_path, original_mode)


def test_ssh_keypair_exists_and_valid():
    private_key = "/home/user/new_jwt_key"
    public_key = "/home/user/new_jwt_key.pub"

    assert os.path.exists(private_key), f"Private key {private_key} is missing."
    assert os.path.isfile(private_key), f"Path {private_key} is not a file."

    assert os.path.exists(public_key), f"Public key {public_key} is missing."
    assert os.path.isfile(public_key), f"Path {public_key} is not a file."

    try:
        result = subprocess.run(
            ["ssh-keygen", "-l", "-f", private_key],
            capture_output=True, text=True, check=True
        )
        assert "ED25519" in result.stdout.upper(), "The generated SSH key is not an ED25519 key."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"ssh-keygen failed to validate the private key: {e.stderr}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
