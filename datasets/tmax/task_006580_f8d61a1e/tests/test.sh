#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess
from datetime import datetime, timezone


def run_openssl(args):
    return subprocess.run(
        ["openssl"] + args,
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_decrypt_source_compiles():
    source_path = "/home/user/decrypt.c"
    assert os.path.exists(source_path), f"Missing required file: {source_path}"
    assert stat.S_ISREG(os.lstat(source_path).st_mode), f"Not a regular C source file: {source_path}"
    assert os.path.getsize(source_path) > 0, f"Empty C source file: {source_path}"

    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", source_path, "-o", "/tmp/decrypt_verifier"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"decrypt.c does not compile: {result.stderr}"
    assert os.path.isfile("/tmp/decrypt_verifier"), "Compilation did not produce an executable"


def test_old_credentials_recovered_and_verified():
    pem_path = "/home/user/old_credentials.pem"
    checksum_path = "/home/user/checksums.txt"
    assert os.path.isfile(pem_path), f"Missing required file: {pem_path}"
    assert os.path.isfile(checksum_path), f"Missing {checksum_path}"

    with open(checksum_path, "r") as f:
        fields = f.read().split()
    assert fields, f"No checksum found in {checksum_path}"
    expected_checksum = fields[0].lower()
    assert re.fullmatch(r"[0-9a-f]{64}", expected_checksum), "Invalid SHA256 in checksums.txt"

    with open(pem_path, "rb") as f:
        actual_checksum = hashlib.sha256(f.read()).hexdigest()
    assert actual_checksum == expected_checksum, (
        f"Recovered old_credentials.pem SHA256 is {actual_checksum}, expected {expected_checksum}"
    )

    result = run_openssl(["pkey", "-in", pem_path, "-check", "-noout"])
    assert result.returncode == 0, f"Recovered file is not a valid private key: {result.stderr}"


def test_rotation_summary():
    summary_path = "/home/user/rotation_summary.txt"
    assert os.path.isfile(summary_path), f"Missing required file: {summary_path}"

    with open(summary_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {summary_path}, got {len(lines)}"
    assert lines[0] == "Trigger IP: 10.0.45.22", f"Line 1 incorrect: {lines[0]}"

    checksum_path = "/home/user/checksums.txt"
    assert os.path.isfile(checksum_path), f"Missing {checksum_path}"
    with open(checksum_path, "r") as f:
        expected_checksum = f.read().split()[0]

    with open("/home/user/old_credentials.pem", "rb") as f:
        actual_checksum = hashlib.sha256(f.read()).hexdigest()
    assert actual_checksum == expected_checksum.lower(), "Summary checksum source does not match recovered key"
    assert lines[1] == f"Old Key Checksum: {expected_checksum}", f"Line 2 incorrect: {lines[1]}"
    assert lines[2] == "New Cert CN: rotated.local", f"Line 3 incorrect: {lines[2]}"


def test_new_credentials_valid_rsa_2048():
    key_path = "/home/user/new_credentials.pem"
    assert os.path.isfile(key_path), f"Missing required file: {key_path}"

    result = run_openssl(["rsa", "-in", key_path, "-check", "-noout"])
    assert result.returncode == 0, f"Invalid RSA key in {key_path}: {result.stderr}"

    details = run_openssl(["rsa", "-in", key_path, "-text", "-noout"])
    assert details.returncode == 0, f"Could not inspect RSA key: {details.stderr}"
    assert re.search(r"(?:Private-Key|RSA Private-Key): \(2048 bit", details.stdout), (
        f"New RSA key is not 2048 bits: {details.stdout.splitlines()[:1]}"
    )


def test_new_cert_valid():
    cert_path = "/home/user/new_cert.pem"
    assert os.path.isfile(cert_path), f"Missing required file: {cert_path}"

    result = run_openssl(["x509", "-in", cert_path, "-noout", "-subject"])
    assert result.returncode == 0, f"Invalid certificate in {cert_path}: {result.stderr}"
    assert "CN" in result.stdout and "rotated.local" in result.stdout, (
        f"Certificate does not have correct CN: {result.stdout}"
    )

    subject = run_openssl(["x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"])
    assert subject.returncode == 0
    match = re.search(r"(?:^|,)CN=([^,]+)", subject.stdout.strip().removeprefix("subject="))
    assert match and match.group(1) == "rotated.local", f"Incorrect certificate CN: {subject.stdout}"

    dates = run_openssl(["x509", "-in", cert_path, "-noout", "-dates"])
    assert dates.returncode == 0, f"Could not read certificate validity: {dates.stderr}"
    values = dict(line.split("=", 1) for line in dates.stdout.strip().splitlines())
    not_before = datetime.strptime(values["notBefore"], "%b %d %H:%M:%S %Y GMT").replace(tzinfo=timezone.utc)
    not_after = datetime.strptime(values["notAfter"], "%b %d %H:%M:%S %Y GMT").replace(tzinfo=timezone.utc)
    assert (not_after - not_before).total_seconds() == 365 * 24 * 60 * 60, (
        f"Certificate validity is not exactly 365 days: {dates.stdout}"
    )
    now = datetime.now(timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid"

    verified = run_openssl(["verify", "-CAfile", cert_path, cert_path])
    assert verified.returncode == 0, f"Certificate is not validly self-signed: {verified.stderr}"


def test_cert_matches_key():
    key_path = "/home/user/new_credentials.pem"
    cert_path = "/home/user/new_cert.pem"

    key_result = run_openssl(["rsa", "-noout", "-modulus", "-in", key_path])
    cert_result = run_openssl(["x509", "-noout", "-modulus", "-in", cert_path])
    assert key_result.returncode == 0, f"Could not extract modulus from private key: {key_result.stderr}"
    assert cert_result.returncode == 0, f"Could not extract modulus from certificate: {cert_result.stderr}"

    key_mod = key_result.stdout.strip()
    cert_mod = cert_result.stdout.strip()
    assert key_mod, "Could not extract modulus from private key"
    assert key_mod == cert_mod, "The certificate does not match the generated private key"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
