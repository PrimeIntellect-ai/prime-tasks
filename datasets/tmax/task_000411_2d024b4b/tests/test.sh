#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
from datetime import timedelta
from email.utils import parsedate_to_datetime


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def test_cert_and_key_exist():
    """Verify that cert.pem and key.pem exist."""
    assert os.path.isfile("/home/user/cert.pem"), "/home/user/cert.pem is missing."
    assert os.path.isfile("/home/user/key.pem"), "/home/user/key.pem is missing."


def test_cert_properties():
    """Verify the certificate is RSA 2048, CN=legacy.internal, and valid for >= 365 days."""
    subject_cmd = ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-subject"]
    result = run(subject_cmd, text=True)
    assert result.returncode == 0, f"Failed to read cert.pem: {result.stderr}"
    assert "CN = legacy.internal" in result.stdout or "CN=legacy.internal" in result.stdout, \
        "Certificate Common Name is not 'legacy.internal'."

    key_cmd = ["openssl", "rsa", "-in", "/home/user/key.pem", "-noout", "-text"]
    result = run(key_cmd, text=True)
    assert result.returncode == 0, f"Failed to read key.pem: {result.stderr}"
    assert "Private-Key: (2048 bit" in result.stdout, "Private key is not 2048-bit RSA."

    # Preserve the original remaining-validity assertion.
    exp_cmd = ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-checkend", "31449600"]
    result = run(exp_cmd, text=True)
    assert result.returncode == 0, "Certificate expires too soon."

    # Verify the actual certificate validity interval is at least 365 days.
    dates = run(
        ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-startdate", "-enddate"],
        text=True,
    )
    assert dates.returncode == 0, f"Failed to read certificate dates: {dates.stderr}"
    values = {}
    for line in dates.stdout.splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            values[name] = parsedate_to_datetime(value)
    assert "notBefore" in values and "notAfter" in values, "Certificate validity dates are missing."
    assert values["notAfter"] - values["notBefore"] >= timedelta(days=365), \
        "Certificate validity interval is less than 365 days."


def test_private_key_matches_certificate():
    """Verify cert.pem contains the public key corresponding to key.pem."""
    cert_modulus = run(
        ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-modulus"],
        text=True,
    )
    key_modulus = run(
        ["openssl", "rsa", "-in", "/home/user/key.pem", "-noout", "-modulus"],
        text=True,
    )
    assert cert_modulus.returncode == 0, f"Failed to read certificate public key: {cert_modulus.stderr}"
    assert key_modulus.returncode == 0, f"Failed to read private key modulus: {key_modulus.stderr}"
    assert cert_modulus.stdout.strip() == key_modulus.stdout.strip(), \
        "The private key does not match the certificate."


def test_generate_token_c_exists():
    """Verify that generate_token.c exists."""
    assert os.path.isfile("/home/user/generate_token.c"), "/home/user/generate_token.c is missing."


def test_token_txt_properties():
    """Verify token.txt exists, is 16 hexadecimal chars long, and has no newline."""
    assert os.path.isfile("/home/user/token.txt"), "/home/user/token.txt is missing."
    with open("/home/user/token.txt", "rb") as f:
        content = f.read()

    assert len(content) == 16, f"token.txt must be exactly 16 characters long, but it is {len(content)} bytes."
    assert b"\n" not in content, "token.txt must not contain newline characters."
    assert re.fullmatch(rb"[0-9A-Fa-f]{16}", content), "token.txt must contain exactly 16 hexadecimal characters."


def expected_token():
    cert_der = run(["openssl", "x509", "-in", "/home/user/cert.pem", "-outform", "DER"])
    assert cert_der.returncode == 0, f"Failed to convert cert.pem to DER: {cert_der.stderr.decode(errors='replace')}"
    fingerprint = hashlib.sha256(cert_der.stdout).digest()[:8]
    key = bytes([0x13, 0x37, 0xBE, 0xEF, 0xAA, 0xBB, 0xCC, 0xDD])
    encrypted = bytes((((fingerprint[i] ^ key[i]) + i) & 0xff) for i in range(8))
    return encrypted.hex()


def test_generate_token_program_compiles_and_runs():
    """Compile and execute the submitted C generator and verify its generated token."""
    src = "/home/user/generate_token.c"
    binary = "/tmp/generate_token_test_bin"
    result = run(["gcc", src, "-o", binary, "-lcrypto"], text=True)
    assert result.returncode == 0, f"Failed to compile generate_token.c:\n{result.stderr}"

    token_path = "/home/user/token.txt"
    with open(token_path, "rb") as f:
        submitted_token = f.read()

    # Remove the pre-existing answer so execution must itself produce a token,
    # either on stdout (for redirection) or directly in token.txt.
    os.unlink(token_path)
    try:
        result = run([binary], cwd="/home/user", text=True, timeout=15)
        assert result.returncode == 0, \
            f"generate_token exited with code {result.returncode}: {result.stderr}"

        candidates = []
        stdout_token = result.stdout.strip()
        if re.fullmatch(r"[0-9A-Fa-f]{16}", stdout_token):
            candidates.append(stdout_token.lower())
        if os.path.isfile(token_path):
            with open(token_path, "rb") as f:
                generated_file = f.read()
            if re.fullmatch(rb"[0-9A-Fa-f]{16}", generated_file):
                candidates.append(generated_file.decode("ascii").lower())

        correct = expected_token()
        assert correct in candidates, \
            "Running generate_token.c did not produce the correct token on stdout or in token.txt."
        assert submitted_token.decode("ascii").lower() == correct, \
            "The submitted token.txt does not contain the token derived from cert.pem."
    finally:
        with open(token_path, "wb") as f:
            f.write(submitted_token)


def test_validator_success():
    """Compile and run validator.c against the generated cert and token."""
    validator_src = "/home/user/validator.c"
    validator_bin = "/home/user/validator"
    cert_path = "/home/user/cert.pem"
    token_path = "/home/user/token.txt"

    assert os.path.isfile(validator_src), f"{validator_src} is missing."

    result = run(["gcc", validator_src, "-o", validator_bin], text=True)
    assert result.returncode == 0, f"Failed to compile validator.c:\n{result.stderr}"

    result = run([validator_bin, cert_path, token_path], text=True)
    assert result.returncode == 0, \
        f"Validator exited with code {result.returncode}. Output: {result.stdout.strip()}"
    assert result.stdout.strip() == "VALID", \
        f"Validator output was not 'VALID'. Output: {result.stdout.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
