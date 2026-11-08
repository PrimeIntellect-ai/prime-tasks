#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import subprocess
from pathlib import Path

DECRYPT_SOURCE = Path("/home/user/decrypt.c")
ENCRYPTED_LOG = Path("/home/user/encrypted_log.bin")
REPORT = Path("/home/user/audit_report.txt")
EXECUTABLE = Path("/tmp/decrypt_submission")
EXPECTED_KEY = "C0mpL1@nc3"
EXPECTED_PAYLOAD = "admin' OR '1'='1' --"


def xor_bytes(data, key):
    return bytes(byte ^ key[i % len(key)] for i, byte in enumerate(data))


def run_as_user(command):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        command,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
        preexec_fn=demote,
        start_new_session=True,
    )


def test_decrypt_c_exists():
    path = "/home/user/decrypt.c"
    assert os.path.exists(path), f"The file {path} is missing."
    assert os.path.isfile(path), f"The path {path} is not a file."


def test_audit_report_exists_and_content():
    report_path = "/home/user/audit_report.txt"
    assert os.path.exists(report_path), f"The report file {report_path} is missing."
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."

    with open(report_path, "r", encoding="utf-8") as f:
        raw_report = f.read()

    lines = [line.strip() for line in raw_report.splitlines() if line.strip()]
    assert len(lines) >= 2, f"The report file {report_path} must contain at least two lines."

    expected_key = EXPECTED_KEY
    assert lines[0] == expected_key, f"The first line of the report is incorrect. Expected {expected_key}, but got {lines[0]}"

    payload = lines[1]
    expected_payload_logic = EXPECTED_PAYLOAD
    assert expected_payload_logic in payload, f"The second line does not contain the correct SQL injection payload logic. Got: {payload}"

    # The requested report must contain exactly the key and exact payload, one per line.
    assert raw_report.splitlines() == [EXPECTED_KEY, EXPECTED_PAYLOAD], \
        "The report must contain exactly two lines: the exact key and the exact payload."


def test_decryptor_compiles_and_decrypts():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", str(DECRYPT_SOURCE), "-o", str(EXECUTABLE)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert compile_result.returncode == 0, \
        f"decrypt.c failed to compile:\n{compile_result.stderr.decode(errors='replace')}"
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK), \
        "Compiling decrypt.c did not produce an executable."

    key = EXPECTED_KEY.encode("ascii")
    original_ciphertext = ENCRYPTED_LOG.read_bytes()
    expected_plaintext = xor_bytes(original_ciphertext, key)

    original_run = run_as_user([str(EXECUTABLE)])
    assert original_run.returncode == 0, \
        f"The decryptor failed on encrypted_log.bin: {original_run.stderr.decode(errors='replace')}"
    assert original_run.stdout == expected_plaintext, \
        "The decryptor's output does not match the decrypted audit log."
    assert EXPECTED_PAYLOAD.encode("utf-8") in original_run.stdout, \
        "The decrypted log does not contain the payload reported in audit_report.txt."

    # Exercise the submitted program on an unpredictable verifier-generated log,
    # preventing a program that merely prints the known plaintext from passing.
    challenge_plaintext = (
        "[INFO] Verification record: " + secrets.token_hex(24) + "\n"
        "[WARN] Query token: " + secrets.token_hex(19) + "\n"
    ).encode("ascii")
    challenge_ciphertext = xor_bytes(challenge_plaintext, key)

    try:
        ENCRYPTED_LOG.write_bytes(challenge_ciphertext)
        challenge_run = run_as_user([str(EXECUTABLE)])
        assert challenge_run.returncode == 0, \
            f"The decryptor failed on a verifier-generated encrypted log: {challenge_run.stderr.decode(errors='replace')}"
        assert challenge_run.stdout == challenge_plaintext, \
            "The decryptor does not correctly implement repeating-key XOR decryption."
    finally:
        ENCRYPTED_LOG.write_bytes(original_ciphertext)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
