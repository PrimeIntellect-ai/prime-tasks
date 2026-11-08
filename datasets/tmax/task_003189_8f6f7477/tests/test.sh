#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

def test_policy_decrypted():
    student_file = "/home/user/policy.txt"
    assert os.path.isfile(student_file), f"File {student_file} does not exist. You must decrypt the policy file to this path."

    # Decrypt the oracle to compare
    oracle_cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-in", "/app/policy_def.enc",
        "-pass", "pass:DevSecOps_attack"
    ]
    res = subprocess.run(oracle_cmd, capture_output=True, text=True)
    assert res.returncode == 0, "Failed to decrypt oracle policy for comparison."
    oracle_text = res.stdout

    with open(student_file, "r") as f:
        student_text = f.read()

    assert student_text.strip() == oracle_text.strip(), "Decrypted policy text does not match the expected output. Did you use the correct derived password?"

def test_enforce_policy_executable():
    script_path = "/home/user/enforce_policy.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_enforce_policy.sh"
    student_path = "/home/user/enforce_policy.sh"

    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} is missing."
    assert os.path.isfile(student_path), f"Student script {student_path} is missing."

    patterns = [
        "redirect_uri=http://evil.com",
        "redirect_uri=https://malicious.org",
        "?q=<script>alert(1)</script>",
        "javascript:void(0)",
        "X-Admin-Access: true\r\nCookie: bypass=1",
        "GET /login?redirect_uri=http://attacker.com&q=<script> HTTP/1.1\r\nX-Admin-Access: true\r\nCookie: bypass=1",
        "redirect_uri=http://",
        "redirect_uri=https://",
        "<script>",
        "javascript:",
        "X-Admin-Access: true",
        "Cookie: bypass="
    ]

    random.seed(42)
    charset = string.printable

    for i in range(5000):
        length = random.randint(10, 250)
        chars = random.choices(charset, k=length)
        input_str = "".join(chars)

        if random.random() < 0.4:
            pattern = random.choice(patterns)
            insert_pos = random.randint(0, len(input_str))
            input_str = input_str[:insert_pos] + pattern + input_str[insert_pos:]

        oracle_res = subprocess.run([oracle_path, input_str], capture_output=True, text=True)
        student_res = subprocess.run([student_path, input_str], capture_output=True, text=True)

        oracle_out = oracle_res.stdout.strip()
        student_out = student_res.stdout.strip()

        assert oracle_out == student_out, (
            f"Output mismatch on fuzz iteration {i}.\n"
            f"Input: {repr(input_str)}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Student): {student_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
