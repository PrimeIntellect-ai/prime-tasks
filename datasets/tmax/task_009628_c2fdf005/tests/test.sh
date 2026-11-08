#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib

def test_decrypted_image_exists_and_correct():
    hex_file = "/home/user/captured_traffic.hex"
    decrypted_file = "/home/user/decrypted_image.png"

    assert os.path.exists(hex_file), f"{hex_file} is missing."
    assert os.path.exists(decrypted_file), f"{decrypted_file} was not created."

    with open(hex_file, "r") as f:
        hex_data = f.read().strip()

    encrypted_bytes = bytes.fromhex(hex_data)
    key = b"\xDE\xAD\xBE\xEF"

    expected_plaintext = bytearray()
    for i in range(len(encrypted_bytes)):
        expected_plaintext.append(encrypted_bytes[i] ^ key[i % len(key)])

    with open(decrypted_file, "rb") as f:
        actual_plaintext = f.read()

    assert actual_plaintext == expected_plaintext, "The decrypted_image.png does not match the expected plaintext."

def test_report_contents():
    report_file = "/home/user/report.txt"
    decrypted_file = "/home/user/decrypted_image.png"

    assert os.path.exists(report_file), f"{report_file} was not created."
    assert os.path.exists(decrypted_file), f"{decrypted_file} is missing."

    with open(decrypted_file, "rb") as f:
        file_bytes = f.read()
    expected_hash = hashlib.sha256(file_bytes).hexdigest()

    with open(report_file, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 3, f"report.txt must contain exactly 3 lines, found {len(lines)}."

    cwe_id = lines[0].upper()
    assert cwe_id in ["CWE-327", "CWE-326"], f"Line 1 expected CWE-327 or CWE-326, got {lines[0]}"

    assert lines[1].lower() == "deadbeef", f"Line 2 expected 'deadbeef', got '{lines[1]}'"

    assert lines[2].lower() == expected_hash, f"Line 3 expected SHA256 '{expected_hash}', got '{lines[2]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
