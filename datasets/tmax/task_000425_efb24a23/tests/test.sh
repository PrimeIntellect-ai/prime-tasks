#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest

def test_decrypted_crt():
    enc_path = "/home/user/cert.enc"
    dec_path = "/home/user/decrypted.crt"

    assert os.path.isfile(dec_path), f"Expected decrypted certificate file {dec_path} does not exist."
    assert os.path.isfile(enc_path), f"Original encrypted file {enc_path} is missing."

    with open(enc_path, 'rb') as f:
        enc_data = f.read()

    # The truth key is 0x4B
    expected_dec_data = bytes([b ^ 0x4B for b in enc_data])

    with open(dec_path, 'rb') as f:
        actual_dec_data = f.read()

    assert actual_dec_data == expected_dec_data, "The decrypted certificate content is incorrect. Ensure the correct XOR key was used."

def test_report_txt():
    report_path = "/home/user/report.txt"
    enc_path = "/home/user/cert.enc"

    assert os.path.isfile(report_path), f"Expected report file {report_path} does not exist."

    with open(enc_path, 'rb') as f:
        enc_data = f.read()

    expected_dec_data = bytes([b ^ 0x4B for b in enc_data])

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(expected_dec_data)
        tmp_name = tmp.name

    try:
        cmd = ["openssl", "x509", "-in", tmp_name, "-noout", "-fingerprint", "-sha256"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        fingerprint = result.stdout.strip().split('=')[1]
    finally:
        os.remove(tmp_name)

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 non-empty lines in report.txt, found {len(lines)}."

    assert lines[0] == "KEY: 0x4B", f"First line incorrect. Expected 'KEY: 0x4B', got '{lines[0]}'."
    assert lines[1] == "SUBJECT_CN: malicious-c2.local", f"Second line incorrect. Expected 'SUBJECT_CN: malicious-c2.local', got '{lines[1]}'."
    assert lines[2] == f"FINGERPRINT: {fingerprint}", f"Third line incorrect. Expected 'FINGERPRINT: {fingerprint}', got '{lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
