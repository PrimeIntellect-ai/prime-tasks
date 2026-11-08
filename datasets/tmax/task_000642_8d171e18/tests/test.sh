#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

INVESTIGATION = "/home/user/investigation"
VALIDATOR_C = os.path.join(INVESTIGATION, "validator.c")
VALIDATOR = os.path.join(INVESTIGATION, "validator")
CA = os.path.join(INVESTIGATION, "ca.pem")
TOKENS = os.path.join(INVESTIGATION, "tokens")


def test_audit_port():
    sshd_config_path = os.path.join(INVESTIGATION, "sshd_config")
    audit_port_path = "/home/user/audit_port.txt"
    assert os.path.exists(audit_port_path), f"{audit_port_path} does not exist."

    expected_port = None
    with open(sshd_config_path, "r") as f:
        ports = [line.split()[1] for line in f if line.startswith("Port ")]
        for p in set(ports):
            if p != "22":
                expected_port = p
                break

    assert expected_port is not None, "Could not find a secondary port in sshd_config."
    with open(audit_port_path, "r") as f:
        actual_port = f.read().strip()
    assert actual_port == expected_port, f"Expected port {expected_port}, but found {actual_port}."


def test_audit_key():
    auth_keys_path = os.path.join(INVESTIGATION, "authorized_keys")
    audit_key_path = "/home/user/audit_key.txt"
    assert os.path.exists(audit_key_path), f"{audit_key_path} does not exist."

    expected_comment = None
    with open(auth_keys_path, "r") as f:
        for line in f:
            if line.startswith("ssh-dss "):
                parts = line.strip().split()
                if len(parts) >= 3:
                    expected_comment = parts[2]
                break

    assert expected_comment is not None, "Could not find ssh-dss key comment in authorized_keys."
    with open(audit_key_path, "r") as f:
        actual_comment = f.read().strip()
    assert actual_comment == expected_comment, f"Expected key comment {expected_comment}, but found {actual_comment}."


def run_validator(path):
    return subprocess.run(
        [VALIDATOR, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )


def assert_validator_result(path, should_be_valid):
    result = run_validator(path)
    expected_code = 0 if should_be_valid else 1
    expected_output = "VALID" if should_be_valid else "INVALID"
    assert result.returncode == expected_code, (
        f"Validator returned {result.returncode} for {path}; expected {expected_code}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Validator output for {path} was {result.stdout!r}; expected {expected_output!r}."
    )


def test_validator_c_fixed():
    assert os.path.isfile(VALIDATOR_C), f"{VALIDATOR_C} does not exist."
    with open(VALIDATOR_C, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "result >= 0" not in content, "The vulnerability (result >= 0) is still present in validator.c."
    assert "result == 1" in content or "1 == result" in content, "The fix (result == 1) was not found in validator.c."


def test_validator_compiled_and_behavior():
    # Preserve the original artifact assertions, then execute the submitted artifact.
    assert os.path.isfile(VALIDATOR), f"Compiled binary {VALIDATOR} does not exist."
    assert os.access(VALIDATOR, os.X_OK), f"Compiled binary {VALIDATOR} is not executable."

    expected = {}
    for name in sorted(os.listdir(TOKENS)):
        if not name.endswith(".pem"):
            continue
        path = os.path.join(TOKENS, name)
        verify = subprocess.run(
            ["openssl", "verify", "-CAfile", CA, path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
        )
        expected[path] = verify.returncode == 0

    assert any(expected.values()), "No CA-valid candidate token was found."
    assert any(not valid for valid in expected.values()), "No invalid candidate token was found."
    for path, valid in expected.items():
        assert_validator_result(path, valid)

    # Exercise an independently generated self-signed certificate, so behavior cannot
    # be faked merely by recognizing the three supplied token filenames.
    with tempfile.TemporaryDirectory() as td:
        cert = os.path.join(td, "untrusted.pem")
        key = os.path.join(td, "untrusted.key")
        generated = subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-keyout", key, "-out", cert, "-days", "1",
             "-subj", "/CN=VerifierUntrusted"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert generated.returncode == 0, f"Could not generate negative test certificate: {generated.stderr}"
        assert_validator_result(cert, False)


def test_valid_token_file():
    valid_token_path = "/home/user/valid_token_file.txt"
    assert os.path.exists(valid_token_path), f"{valid_token_path} does not exist."

    expected_token = None
    for token_file in os.listdir(TOKENS):
        if not token_file.endswith(".pem"):
            continue
        token_path = os.path.join(TOKENS, token_file)
        result = subprocess.run(
            ["openssl", "verify", "-CAfile", CA, token_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if result.returncode == 0:
            expected_token = token_file
            break

    assert expected_token is not None, "Could not find a valid token signed by the CA."
    with open(valid_token_path, "r") as f:
        actual_token = f.read().strip()
    assert actual_token == expected_token, f"Expected valid token {expected_token}, but found {actual_token}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
