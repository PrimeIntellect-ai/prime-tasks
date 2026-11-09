#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import subprocess
import ssl
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import pytest

REPORT_PATH = "/home/user/rotation_report.json"
BACKUP_PATH = "/home/user/backup.tar.gz"
NEW_CERT_PATH = "/home/user/new_cert.pem"
NEW_KEY_PATH = "/home/user/new_key.pem"
EXPECTED_OLD_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
EXPECTED_REPORT_KEYS = {
    "old_pinned_hash",
    "new_cert_hash",
    "backup_integrity_hash",
}


def load_report():
    with open(REPORT_PATH, "r") as f:
        return json.load(f)


def test_report_exists_and_valid_json():
    """Test that the rotation report exists, is valid JSON, and has exactly the required keys."""
    assert os.path.isfile(REPORT_PATH), f"Report not found at {REPORT_PATH}"
    try:
        data = load_report()
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert isinstance(data, dict), "Report must contain a JSON object."
    assert set(data.keys()) == EXPECTED_REPORT_KEYS, (
        f"Report must have exactly these keys: {sorted(EXPECTED_REPORT_KEYS)}"
    )


def test_old_pinned_hash():
    """Test that the old pinned hash is correctly extracted."""
    data = load_report()
    assert data["old_pinned_hash"] == EXPECTED_OLD_HASH, "old_pinned_hash does not match expected value."


def test_backup_integrity_hash():
    """Test that the backup integrity hash is correct."""
    assert os.path.isfile(BACKUP_PATH), f"Backup file not found at {BACKUP_PATH}"

    sha256 = hashlib.sha256()
    with open(BACKUP_PATH, "rb") as f:
        sha256.update(f.read())
    expected_backup_hash = sha256.hexdigest()

    data = load_report()
    assert data["backup_integrity_hash"] == expected_backup_hash, "backup_integrity_hash is incorrect."


def test_new_certificate_generated_and_hash_correct():
    """Test that the new certificate is generated correctly and its DER hash matches the report."""
    assert os.path.isfile(NEW_CERT_PATH), f"New certificate not found at {NEW_CERT_PATH}"
    assert os.path.isfile(NEW_KEY_PATH), f"New private key not found at {NEW_KEY_PATH}"

    result = subprocess.run(
        ["openssl", "x509", "-in", NEW_CERT_PATH, "-outform", "DER"],
        capture_output=True,
        check=True,
    )
    expected_cert_hash = hashlib.sha256(result.stdout).hexdigest()

    data = load_report()
    assert data["new_cert_hash"] == expected_cert_hash, "new_cert_hash does not match the actual DER hash of the new certificate."


def test_new_certificate_subject():
    """Test that the certificate Common Name is exactly secure.example.com."""
    decoded = ssl._ssl._test_decode_cert(NEW_CERT_PATH)
    common_names = [
        value
        for rdn in decoded.get("subject", ())
        for key, value in rdn
        if key == "commonName"
    ]
    assert common_names == ["secure.example.com"], (
        f"Certificate must have exactly one CN equal to secure.example.com; got {common_names!r}"
    )


def test_private_key_is_2048_bit_rsa():
    """Test that the generated private key is a valid 2048-bit RSA key."""
    check = subprocess.run(
        ["openssl", "rsa", "-in", NEW_KEY_PATH, "-check", "-noout"],
        capture_output=True,
        text=True,
    )
    assert check.returncode == 0, f"Private key is not a valid RSA key: {check.stderr}"

    details = subprocess.run(
        ["openssl", "pkey", "-in", NEW_KEY_PATH, "-text", "-noout"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert re.search(r"Private-Key:\s*\(2048 bit(?:,|\))", details), "RSA private key is not 2048-bit."


def test_certificate_matches_private_key():
    """Test that the certificate contains the public key corresponding to the private key."""
    key_public_der = subprocess.run(
        ["openssl", "pkey", "-in", NEW_KEY_PATH, "-pubout", "-outform", "DER"],
        capture_output=True,
        check=True,
    ).stdout

    cert_public_pem = subprocess.run(
        ["openssl", "x509", "-in", NEW_CERT_PATH, "-pubkey", "-noout"],
        capture_output=True,
        check=True,
    ).stdout
    cert_public_der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_public_pem,
        capture_output=True,
        check=True,
    ).stdout

    assert key_public_der == cert_public_der, "Certificate public key does not match the private key."


def test_certificate_is_self_signed():
    """Test that the certificate issuer equals its subject and its self-signature verifies."""
    decoded = ssl._ssl._test_decode_cert(NEW_CERT_PATH)
    assert decoded.get("issuer") == decoded.get("subject"), "Certificate issuer and subject differ."

    verify = subprocess.run(
        ["openssl", "verify", "-check_ss_sig", "-CAfile", NEW_CERT_PATH, NEW_CERT_PATH],
        capture_output=True,
        text=True,
    )
    assert verify.returncode == 0, f"Certificate self-signature verification failed: {verify.stderr}"


def test_certificate_valid_for_365_days():
    """Test that the certificate is currently valid and has an exact 365-day validity period."""
    dates = subprocess.run(
        ["openssl", "x509", "-in", NEW_CERT_PATH, "-noout", "-dates"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    values = dict(line.split("=", 1) for line in dates if "=" in line)
    assert "notBefore" in values and "notAfter" in values, "Could not read certificate validity dates."

    not_before = parsedate_to_datetime(values["notBefore"])
    not_after = parsedate_to_datetime(values["notAfter"])
    if not_before.tzinfo is None:
        not_before = not_before.replace(tzinfo=timezone.utc)
    if not_after.tzinfo is None:
        not_after = not_after.replace(tzinfo=timezone.utc)

    assert (not_after - not_before).total_seconds() == 365 * 24 * 60 * 60, (
        "Certificate validity period is not exactly 365 days."
    )
    now = datetime.now(timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
