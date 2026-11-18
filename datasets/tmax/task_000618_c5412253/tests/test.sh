#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_vuln_report():
    auth_file = "/home/user/project/auth_module.c"
    report_file = "/home/user/vuln_report.txt"

    assert os.path.isfile(auth_file), f"{auth_file} is missing, cannot compute expected report"
    assert os.path.isfile(report_file), f"{report_file} is missing"

    expected_lines = []
    banned_funcs = ["gets", "strcpy", "sprintf"]

    with open(auth_file, "r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            for func in banned_funcs:
                if re.search(rf'\b{func}\b', line):
                    expected_lines.append(f"{i}: {func}")

    with open(report_file, "r", encoding="utf-8") as f:
        actual_lines = [l.strip() for l in f.readlines() if l.strip()]

    assert actual_lines == expected_lines, f"Vulnerability report contents are incorrect. Expected {expected_lines}, got {actual_lines}"

def test_audit_log_dec():
    enc_file = "/home/user/project/audit_log.enc"
    dec_file = "/home/user/audit_log.dec"

    assert os.path.isfile(enc_file), f"{enc_file} is missing, cannot compute expected decryption"
    assert os.path.isfile(dec_file), f"{dec_file} is missing"

    with open(enc_file, "rb") as f:
        enc_data = f.read()

    known_header = b"SECURE_LOG_V1"
    assert len(enc_data) >= len(known_header), "Encrypted file is too short to contain the header"

    # Derive the 4-byte key from the known plaintext header
    key = bytearray()
    for i in range(4):
        key.append(enc_data[i] ^ known_header[i])

    expected_dec = bytearray()
    for i in range(len(enc_data)):
        expected_dec.append(enc_data[i] ^ key[i % 4])

    with open(dec_file, "rb") as f:
        actual_dec = f.read()

    assert actual_dec == expected_dec, "Decrypted log does not match the expected plaintext output"

def test_token():
    enc_file = "/home/user/project/audit_log.enc"
    token_file = "/home/user/token.txt"

    assert os.path.isfile(enc_file), f"{enc_file} is missing, cannot compute expected token"
    assert os.path.isfile(token_file), f"{token_file} is missing"

    with open(enc_file, "rb") as f:
        enc_data = f.read()

    known_header = b"SECURE_LOG_V1"
    key = bytearray()
    for i in range(4):
        key.append(enc_data[i] ^ known_header[i])

    expected_dec = bytearray()
    for i in range(len(enc_data)):
        expected_dec.append(enc_data[i] ^ key[i % 4])

    match = re.search(b"TOKEN-[A-Z0-9]{16}", expected_dec)
    assert match is not None, "Token pattern not found in the expected decrypted log"
    expected_token = match.group(0)

    with open(token_file, "rb") as f:
        actual_token_bytes = f.read()

    assert actual_token_bytes == expected_token, f"Token file content is incorrect. Expected {expected_token.decode()}, got {actual_token_bytes.decode(errors='replace')}"
    assert not actual_token_bytes.endswith(b"\n"), "Token file must not contain a trailing newline"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
