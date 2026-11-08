#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import re
from datetime import datetime
import pytest

def test_suid_audit():
    audit_file = "/home/user/audit_suid.txt"
    assert os.path.exists(audit_file), f"File {audit_file} is missing."

    with open(audit_file, "r") as f:
        content = f.read().strip()

    expected_path = "/home/user/service/bin/helper"
    assert content == expected_path, f"Expected {audit_file} to contain {expected_path}, but got '{content}'."

    helper_stat = os.stat(expected_path)
    assert not (helper_stat.st_mode & stat.S_ISUID), f"SUID bit is still set on {expected_path}."

def test_file_integrity():
    comp_file = "/home/user/compromised_file.txt"
    assert os.path.exists(comp_file), f"File {comp_file} is missing."

    with open(comp_file, "r") as f:
        content = f.read().strip()

    expected_path = "/home/user/service/public/config.js"
    assert content == expected_path, f"Expected {comp_file} to contain {expected_path}, but got '{content}'."

def test_cookie_extraction():
    cookie_file = "/home/user/stolen_cookie.txt"
    assert os.path.exists(cookie_file), f"File {cookie_file} is missing."

    with open(cookie_file, "r") as f:
        content = f.read().strip()

    expected_cookie = "supersecrettoken99"
    assert content == expected_cookie, f"Expected {cookie_file} to contain '{expected_cookie}', but got '{content}'."

def test_cert_rotation():
    crt_path = "/home/user/service/cert/server.crt"
    key_path = "/home/user/service/cert/server.key"

    assert os.path.exists(crt_path), f"Certificate {crt_path} is missing."
    assert os.path.exists(key_path), f"Private key {key_path} is missing."

    # Check Subject / Common Name
    subj_out = subprocess.check_output(["openssl", "x509", "-in", crt_path, "-noout", "-subject"], text=True)
    assert "CN = localhost" in subj_out or "CN=localhost" in subj_out, f"Certificate Common Name is not 'localhost'. Subject: {subj_out}"

    # Check Modulus to ensure cert and key match
    crt_mod = subprocess.check_output(["openssl", "x509", "-in", crt_path, "-noout", "-modulus"], text=True).strip()
    key_mod = subprocess.check_output(["openssl", "rsa", "-in", key_path, "-noout", "-modulus"], text=True).strip()
    assert crt_mod == key_mod, "Certificate and private key do not match."

    # Check key size
    text_out = subprocess.check_output(["openssl", "rsa", "-in", key_path, "-noout", "-text"], text=True)
    assert "Private-Key: (2048 bit" in text_out, "Private key is not 2048-bit."

    # Check that the certificate is actually self-signed, including its signature.
    verify_result = subprocess.run(
        ["openssl", "verify", "-check_ss_sig", "-CAfile", crt_path, crt_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert verify_result.returncode == 0, f"Certificate is not validly self-signed: {verify_result.stdout}"

    # Check expiration (30 days)
    dates_out = subprocess.check_output(["openssl", "x509", "-in", crt_path, "-noout", "-dates"], text=True)

    not_before_match = re.search(r"notBefore=(.*)", dates_out)
    not_after_match = re.search(r"notAfter=(.*)", dates_out)

    assert not_before_match and not_after_match, "Could not parse certificate dates."

    def parse_date(d_str):
        d_str = re.sub(r'\s+', ' ', d_str.strip())
        return datetime.strptime(d_str, "%b %d %H:%M:%S %Y %Z")

    not_before = parse_date(not_before_match.group(1))
    not_after = parse_date(not_after_match.group(1))

    diff = not_after - not_before
    assert diff.days == 30, f"Certificate is valid for {diff.days} days, expected exactly 30 days."
    assert diff.total_seconds() == 30 * 24 * 60 * 60, f"Certificate validity is {diff}, expected exactly 30 days."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
