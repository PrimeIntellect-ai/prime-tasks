#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import stat
import subprocess
import pytest

CERT_PATH = "/home/user/certs/new_cert.pem"
KEY_PATH = "/home/user/certs/new_key.pem"
FINGERPRINT_PATH = "/home/user/rotated_fingerprint.txt"
EXPECTED_CN = "secops.internal.rotator.v1"


def run_openssl(args):
    try:
        return subprocess.run(
            ["openssl"] + args,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        stderr = getattr(e, "stderr", "")
        pytest.fail(f"OpenSSL command failed: openssl {' '.join(args)}\n{stderr}")


def test_files_exist():
    assert os.path.exists(CERT_PATH), f"Certificate file {CERT_PATH} is missing."
    assert os.path.isfile(CERT_PATH), f"{CERT_PATH} is not a file."

    assert os.path.exists(KEY_PATH), f"Private key file {KEY_PATH} is missing."
    assert os.path.isfile(KEY_PATH), f"{KEY_PATH} is not a file."

    assert os.path.exists(FINGERPRINT_PATH), f"Fingerprint file {FINGERPRINT_PATH} is missing."
    assert os.path.isfile(FINGERPRINT_PATH), f"{FINGERPRINT_PATH} is not a file."


def test_permissions():
    key_stat = os.stat(KEY_PATH)
    cert_stat = os.stat(CERT_PATH)

    key_perms = stat.S_IMODE(key_stat.st_mode)
    cert_perms = stat.S_IMODE(cert_stat.st_mode)

    assert key_perms == 0o600, f"Expected {KEY_PATH} permissions to be 600, but got {oct(key_perms)}."
    assert cert_perms == 0o644, f"Expected {CERT_PATH} permissions to be 644, but got {oct(cert_perms)}."


def test_certificate_cn():
    result = run_openssl(["x509", "-in", CERT_PATH, "-noout", "-subject"])
    subject = result.stdout.strip()
    assert EXPECTED_CN in subject, f"Expected CN '{EXPECTED_CN}' not found in certificate subject: {subject}"

    detailed = run_openssl([
        "x509", "-in", CERT_PATH, "-noout", "-subject",
        "-nameopt", "sep_multiline,utf8"
    ]).stdout
    cn_values = []
    for line in detailed.splitlines():
        item = line.strip()
        if "=" in item:
            field, value = item.split("=", 1)
            if field.strip() == "CN":
                cn_values.append(value.strip())
    assert cn_values == [EXPECTED_CN], (
        f"Certificate must have exactly one CN equal to '{EXPECTED_CN}', got {cn_values}."
    )


def test_private_key_is_unencrypted_rsa_2048():
    with open(KEY_PATH, "rb") as f:
        key_data = f.read()
    assert b"ENCRYPTED PRIVATE KEY" not in key_data, "Private key must not be encrypted."
    assert not (b"Proc-Type:" in key_data and b"ENCRYPTED" in key_data), "Private key must not be encrypted."

    run_openssl(["rsa", "-in", KEY_PATH, "-check", "-noout"])
    key_text = run_openssl(["pkey", "-in", KEY_PATH, "-text", "-noout"]).stdout
    assert re.search(r"Private-Key:\s*\(2048 bit(?:,|\))", key_text), (
        "Private key must be a 2048-bit RSA key."
    )


def test_certificate_matches_private_key():
    cert_pub = run_openssl(["x509", "-in", CERT_PATH, "-pubkey", "-noout"]).stdout
    key_pub = run_openssl(["pkey", "-in", KEY_PATH, "-pubout"]).stdout
    assert cert_pub == key_pub, "Certificate public key does not match the private key."


def test_certificate_is_self_signed():
    names = run_openssl([
        "x509", "-in", CERT_PATH, "-noout", "-subject", "-issuer",
        "-nameopt", "RFC2253"
    ]).stdout.strip().splitlines()
    assert len(names) == 2, f"Could not read certificate subject and issuer: {names}"
    subject = names[0].split("=", 1)[1].strip()
    issuer = names[1].split("=", 1)[1].strip()
    assert subject == issuer, f"Certificate is not self-issued: subject={subject}, issuer={issuer}"

    run_openssl(["verify", "-CAfile", CERT_PATH, CERT_PATH])


def test_certificate_validity_is_365_days():
    output = run_openssl(["x509", "-in", CERT_PATH, "-noout", "-dates"]).stdout
    values = {}
    for line in output.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    assert "notBefore" in values and "notAfter" in values, "Certificate validity dates are missing."

    date_format = "%b %d %H:%M:%S %Y GMT"
    not_before = datetime.datetime.strptime(values["notBefore"], date_format)
    not_after = datetime.datetime.strptime(values["notAfter"], date_format)
    assert not_after - not_before == datetime.timedelta(days=365), (
        f"Certificate validity must be exactly 365 days, got {not_after - not_before}."
    )


def test_fingerprint_match():
    result = run_openssl([
        "x509", "-in", CERT_PATH, "-noout", "-fingerprint", "-sha256"
    ])
    expected_fingerprint = result.stdout.strip()

    with open(FINGERPRINT_PATH, "r") as f:
        actual_fingerprint = f.read().strip()

    assert actual_fingerprint == expected_fingerprint, (
        f"Fingerprint in {FINGERPRINT_PATH} does not match the certificate's actual fingerprint.\n"
        f"Expected: {expected_fingerprint}\n"
        f"Got: {actual_fingerprint}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
