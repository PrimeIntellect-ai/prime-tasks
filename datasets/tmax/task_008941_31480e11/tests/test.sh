#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest


def get_fingerprint(pubkey_path):
    try:
        output = subprocess.check_output(['ssh-keygen', '-l', '-f', pubkey_path], text=True)
        return output.split()[1]
    except Exception as e:
        pytest.fail(f"Failed to get fingerprint for {pubkey_path}: {e}")


def get_token_validity():
    tokens_file = "/home/user/tokens.txt"
    if not os.path.exists(tokens_file):
        pytest.fail(f"{tokens_file} is missing.")

    validity = {}
    with open(tokens_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) == 3:
                username, timestamp, expected_checksum = parts
                actual_sum = sum(ord(c) for c in username + timestamp)
                is_valid = (actual_sum % 256) == int(expected_checksum)
                validity[username] = "Yes" if is_valid else "No"
    return validity


def interpreted_result(executable, username, timestamp, checksum):
    try:
        result = subprocess.run(
            [executable, username, timestamp, str(checksum)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
    except Exception as e:
        pytest.fail(f"Failed to execute {executable}: {e}")

    text = (result.stdout + "\n" + result.stderr).strip().lower()
    if re.search(r"\binvalid\b|\bnot valid\b|\bfalse\b|\bno\b", text):
        return False
    if re.search(r"\bvalid\b|\btrue\b|\byes\b", text):
        return True
    if text in {"0", "1"}:
        return text == "1"

    # Programs that communicate validation through the conventional exit status
    # are also accepted.
    return result.returncode == 0


def assert_validator_behavior(executable):
    cases = [("abc", "123")]
    alphabet = string.ascii_letters + string.digits + "_-"
    for _ in range(8):
        username = "u" + "".join(secrets.choice(alphabet) for _ in range(11))
        timestamp = str(secrets.randbelow(9_000_000_000) + 1_000_000_000)
        cases.append((username, timestamp))

    for username, timestamp in cases:
        correct = sum(ord(c) for c in username + timestamp) % 256
        wrong = (correct + secrets.randbelow(255) + 1) % 256
        assert interpreted_result(executable, username, timestamp, correct) is True, \
            f"{executable} rejected a valid checksum for {username!r}, {timestamp!r}."
        assert interpreted_result(executable, username, timestamp, wrong) is False, \
            f"{executable} accepted an invalid checksum for {username!r}, {timestamp!r}."


def test_c_program_exists():
    assert os.path.isfile("/home/user/validate.c"), "/home/user/validate.c is missing."
    assert os.path.isfile("/home/user/validate"), "/home/user/validate executable is missing."
    assert os.access("/home/user/validate", os.X_OK), "/home/user/validate is not executable."


def test_c_program_behavior():
    source = "/home/user/validate.c"
    executable = "/home/user/validate"

    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/validate is not a compiled executable."

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "validate-rebuilt")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert compile_result.returncode == 0, \
            f"/home/user/validate.c does not compile successfully: {compile_result.stderr}"

        # Test both the submitted executable and an independently rebuilt copy so
        # that the source and compiled artifact must implement the validation rule.
        assert_validator_behavior(executable)
        assert_validator_behavior(rebuilt)


def test_compliance_audit_csv():
    audit_file = "/home/user/compliance_audit.csv"
    assert os.path.isfile(audit_file), f"{audit_file} is missing."

    pubkeys_dir = "/home/user/pubkeys"
    fp_to_user = {}
    for filename in os.listdir(pubkeys_dir):
        if filename.endswith(".pub"):
            username = filename[:-4]
            fp = get_fingerprint(os.path.join(pubkeys_dir, filename))
            fp_to_user[fp] = username

    token_validity = get_token_validity()

    expected_lines = []
    auth_file = "/home/user/auth_events.log"
    with open(auth_file, "r") as f:
        for line in f:
            if "Accepted publickey" in line:
                parts = line.strip().split()
                fp = parts[-1]
                username = fp_to_user.get(fp)
                if not username:
                    pytest.fail(f"Fingerprint {fp} found in log but does not match any public key.")

                valid = token_validity.get(username, "No")
                expected_lines.append(f"{username},{fp},{valid}")

    with open(audit_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in CSV, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
