#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import subprocess
import pytest

def check_permissions(path, expected_mode):
    try:
        mode = os.stat(path).st_mode & 0o777
        return mode == expected_mode
    except FileNotFoundError:
        return False

def check_hash(path, expected_hash):
    try:
        with open(path, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest() == expected_hash
    except FileNotFoundError:
        return False

def check_cert(path, expected_cn):
    try:
        output = subprocess.check_output(
            ['openssl', 'x509', '-noout', '-subject', '-in', path],
            stderr=subprocess.STDOUT
        ).decode()
        return f"CN = {expected_cn}" in output or f"CN={expected_cn}" in output
    except Exception:
        return False

def check_private_key_matches_cert(key_path, cert_path):
    try:
        key_check = subprocess.run(
            ['openssl', 'pkey', '-in', key_path, '-check', '-noout'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10
        )
        if key_check.returncode != 0:
            return False

        key_public = subprocess.check_output(
            ['openssl', 'pkey', '-in', key_path, '-pubout', '-outform', 'DER'],
            stderr=subprocess.STDOUT,
            timeout=10
        )
        cert_public_pem = subprocess.check_output(
            ['openssl', 'x509', '-in', cert_path, '-pubkey', '-noout'],
            stderr=subprocess.STDOUT,
            timeout=10
        )
        cert_public = subprocess.check_output(
            ['openssl', 'pkey', '-pubin', '-outform', 'DER'],
            input=cert_public_pem,
            stderr=subprocess.STDOUT,
            timeout=10
        )
        return key_public == cert_public
    except Exception:
        return False

def check_vuln_report():
    try:
        with open('/home/user/vuln_report.json', 'r') as f:
            data = json.load(f)
            if not isinstance(data, list):
                return False
            expected = {
                '/home/user/app/source/main.py',
                '/home/user/app/source/config.js'
            }
            return set(data) == expected
    except Exception:
        return False

def test_security_posture_score():
    points = 0
    total = 5
    failures = []

    # 1. config.yml permissions (0600)
    if check_permissions('/home/user/app/config.yml', 0o600):
        points += 1
    else:
        failures.append("config.yml does not have 0600 permissions")

    # 2. server.key permissions (0400)
    if check_permissions('/home/user/app/certs/server.key', 0o400):
        points += 1
    else:
        failures.append("server.key does not have 0400 permissions")

    # 3. secure_exec hash (backup_B.bin)
    target_hash = hashlib.sha256(b"echo 'correct binary v2'\n").hexdigest()
    if check_hash('/home/user/app/bin/secure_exec', target_hash):
        points += 1
    else:
        failures.append("secure_exec does not match the expected SHA-256 hash")

    # 4. TLS certificate CN, private-key validity, and certificate/key match
    cert_path = '/home/user/app/certs/server.crt'
    key_path = '/home/user/app/certs/server.key'
    cert_ok = check_cert(cert_path, 'secure-internal.local')
    key_ok = check_private_key_matches_cert(key_path, cert_path)
    if cert_ok and key_ok:
        points += 1
    else:
        if not cert_ok:
            failures.append("server.crt does not have the expected CN 'secure-internal.local'")
        if not key_ok:
            failures.append("server.key is not a valid private key matching server.crt")

    # 5. Vulnerability report
    if check_vuln_report():
        points += 1
    else:
        failures.append("vuln_report.json is missing, malformed, or contains incorrect findings")

    score = points / total

    assert score >= 1.0, (
        f"Security Posture Score is {score} (threshold >= 1.0). "
        f"Passed {points}/{total} checks. "
        f"Failures: {', '.join(failures)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
