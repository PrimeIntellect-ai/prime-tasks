#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
from datetime import datetime


def test_tls_certificate():
    """Test that the TLS certificate and private key are generated correctly."""
    cert_file = "/home/user/certs/new_cert.pem"
    key_file = "/home/user/certs/new_key.pem"

    assert os.path.isfile(cert_file), f"Certificate file {cert_file} does not exist."
    assert os.path.isfile(key_file), f"Private key file {key_file} does not exist."

    # Check if CN is localhost
    result = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-subject"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to read certificate with openssl."
    assert "CN = localhost" in result.stdout or "CN=localhost" in result.stdout, "Certificate Common Name (CN) is not localhost."

    # Check if private key is valid RSA
    result_key = subprocess.run(
        ["openssl", "rsa", "-in", key_file, "-check", "-noout"],
        capture_output=True, text=True
    )
    assert result_key.returncode == 0, "Private key is not a valid RSA key."

    # Check that the RSA key is exactly 2048 bits.
    modulus = subprocess.run(
        ["openssl", "rsa", "-in", key_file, "-noout", "-modulus"],
        capture_output=True, text=True
    )
    assert modulus.returncode == 0, "Could not read the RSA key modulus."
    assert modulus.stdout.startswith("Modulus="), "Unexpected RSA modulus output."
    modulus_value = int(modulus.stdout.strip().split("=", 1)[1], 16)
    assert modulus_value.bit_length() == 2048, "Private key is not 2048 bits."

    # Check that the certificate public key matches the private key.
    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-pubkey"],
        capture_output=True
    )
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_file, "-pubout"],
        capture_output=True
    )
    assert cert_pub.returncode == 0, "Could not extract the certificate public key."
    assert key_pub.returncode == 0, "Could not derive the private key's public key."
    assert cert_pub.stdout == key_pub.stdout, "Certificate and private key do not match."

    # Check that the encoded validity interval is exactly 30 days.
    dates = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-startdate", "-enddate"],
        capture_output=True, text=True
    )
    assert dates.returncode == 0, "Could not read certificate validity dates."
    date_values = {}
    for line in dates.stdout.splitlines():
        name, value = line.split("=", 1)
        date_values[name] = datetime.strptime(value, "%b %d %H:%M:%S %Y %Z")
    assert "notBefore" in date_values and "notAfter" in date_values, "Certificate validity dates are missing."
    assert (date_values["notAfter"] - date_values["notBefore"]).total_seconds() == 30 * 24 * 60 * 60, "Certificate validity is not exactly 30 days."


def test_key_permissions():
    """Test that the private key permissions are set to 400."""
    key_file = "/home/user/certs/new_key.pem"
    assert os.path.isfile(key_file), f"Private key file {key_file} does not exist."

    st = os.stat(key_file)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Permissions of {key_file} are {oct(permissions)}, expected 0o400."


def test_log_redaction():
    """Test that the log is an exact redaction and the source was not modified."""
    source_log_file = "/home/user/logs/app.log"
    clean_log_file = "/home/user/logs/app_clean.log"
    assert os.path.isfile(source_log_file), f"Original log file {source_log_file} does not exist."
    assert os.path.isfile(clean_log_file), f"Redacted log file {clean_log_file} does not exist."

    original_expected = (
        b"2023-10-01 10:00:01 INFO Server started\n"
        b"2023-10-01 10:05:22 DEBUG Received payload API_KEY=v1_secret_9982_abcd\n"
        b"2023-10-01 10:06:00 ERROR Upload failed\n"
        b"2023-10-01 10:10:15 DEBUG Retry upload API_KEY=v1_secret_9982_abcd\n"
    )
    with open(source_log_file, "rb") as f:
        original = f.read()
    assert original == original_expected, "The original log file was modified."

    with open(clean_log_file, "rb") as f:
        clean_bytes = f.read()
    expected_clean = re.sub(rb"API_KEY=[^\s]+", b"API_KEY=REDACTED", original)
    assert clean_bytes == expected_clean, "Redacted log does not preserve all original content with only API key values replaced."

    with open(clean_log_file, "r") as f:
        content = f.read()
    assert "v1_secret_9982_abcd" not in content, "Original API key still found in the redacted log."
    assert content.count("API_KEY=REDACTED") == 2, "Expected exactly 2 instances of API_KEY=REDACTED in the log."
    assert "2023-10-01 10:00:01 INFO Server started" in content, "Original non-sensitive log lines are missing."


def test_exploit_payload():
    """Test that the exploit payload file exists with correct content and permissions."""
    payload_file = "/home/user/uploads/test_payload.txt"
    assert os.path.isfile(payload_file), f"Payload file {payload_file} does not exist."

    with open(payload_file, "r") as f:
        content = f.read()

    assert content.strip() == "../../etc/passwd", "Payload file content is incorrect."

    st = os.stat(payload_file)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o600, f"Permissions of {payload_file} are {oct(permissions)}, expected 0o600."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
