#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import base64
import json
import secrets
import string
from datetime import datetime, timezone
import pytest


def test_legacy_monitor_permissions():
    """Verify that legacy_monitor has SUID/SGID removed and permissions set to 0755."""
    binary_path = "/home/user/bin/legacy_monitor"
    assert os.path.isfile(binary_path), f"Binary {binary_path} is missing."

    file_stat = os.stat(binary_path)
    mode = stat.S_IMODE(file_stat.st_mode)

    assert not (file_stat.st_mode & stat.S_ISUID), f"SUID bit is still set on {binary_path}."
    assert not (file_stat.st_mode & stat.S_ISGID), f"SGID bit is still set on {binary_path}."
    assert oct(mode) == '0o755', f"Permissions on {binary_path} are {oct(mode)}, expected 0o755."


def _openssl(*args, input_data=None):
    return subprocess.run(
        ["openssl", *args], input=input_data,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
    )


def _parse_openssl_time(value):
    return datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)


def test_root_ca_certificate():
    """Verify the certificate is self-signed, RSA-2048, and valid for exactly 365 days."""
    cert_path = "/home/user/.hidden_trust/root_ca.crt"
    assert os.path.isfile(cert_path), f"Certificate {cert_path} is missing."

    # Preserve the original X.509 parsing assertion.
    result = _openssl("x509", "-in", cert_path, "-noout")
    assert result.returncode == 0, (
        f"File at {cert_path} is not a valid X.509 certificate. "
        f"Error: {result.stderr.decode()}"
    )

    subject = _openssl("x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253")
    issuer = _openssl("x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253")
    assert subject.returncode == 0 and issuer.returncode == 0
    subject_name = subject.stdout.decode().strip().removeprefix("subject=")
    issuer_name = issuer.stdout.decode().strip().removeprefix("issuer=")
    assert subject_name == issuer_name, "Certificate subject and issuer differ; it is not self-signed."

    verify = _openssl("verify", "-CAfile", cert_path, cert_path)
    assert verify.returncode == 0, f"Certificate does not verify with its own public key: {verify.stderr.decode()}"

    text = _openssl("x509", "-in", cert_path, "-noout", "-text")
    assert text.returncode == 0
    cert_text = text.stdout.decode()
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate key is not RSA."
    assert "Public-Key: (2048 bit)" in cert_text, "Certificate does not use a 2048-bit RSA key."

    dates = _openssl("x509", "-in", cert_path, "-noout", "-dates")
    assert dates.returncode == 0
    values = dict(line.split("=", 1) for line in dates.stdout.decode().splitlines())
    not_before = _parse_openssl_time(values["notBefore"])
    not_after = _parse_openssl_time(values["notAfter"])
    assert not_after - not_before == __import__('datetime').timedelta(days=365), (
        f"Certificate validity is {not_after - not_before}, expected exactly 365 days."
    )
    now = datetime.now(timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def _run_validator(path, header):
    return subprocess.run(
        [path, header], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def _assert_invalid(path, header):
    result = _run_validator(path, header)
    assert result.returncode != 0, f"Validator returned success for rejected header {header!r}."
    assert result.stdout.strip() == "INVALID", f"Expected INVALID for {header!r}, got {result.stdout!r}."


def _assert_valid(path, header):
    result = _run_validator(path, header)
    assert result.returncode == 0, f"Validator rejected allowed header {header!r}: {result.stderr!r}"
    assert result.stdout.strip() == "VALID", f"Expected VALID for {header!r}, got {result.stdout!r}."


def test_jwt_auth_compiled_and_fixed(tmp_path):
    """Compile the submitted source and exercise both it and the requested executable."""
    source_path = "/home/user/jwt_auth.cpp"
    bin_path = "/home/user/jwt_auth"
    assert os.path.isfile(source_path), f"Source {source_path} is missing."
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."

    rebuilt = str(tmp_path / "jwt_auth_rebuilt")
    compile_result = subprocess.run(
        ["g++", source_path, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compile_result.returncode == 0, f"Submitted C++ source does not compile: {compile_result.stderr}"

    # Preserve the original two checks on the requested binary.
    result_lower = _run_validator(bin_path, '{"alg":"none"}')
    assert "INVALID" in result_lower.stdout, "jwt_auth did not output 'INVALID' for 'alg: none'."
    result_upper = _run_validator(bin_path, '{"alg":"NONE"}')
    assert "INVALID" in result_upper.stdout, "jwt_auth did not output 'INVALID' for 'alg: NONE'."

    # Test every capitalization, field placement/spacing, and a missing alg field.
    none_variants = []
    for mask in range(16):
        none_variants.append(''.join(
            ch.upper() if mask & (1 << i) else ch.lower()
            for i, ch in enumerate("none")
        ))

    random_alg = "A" + ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))
    rejected = ['{}', '{"typ":"JWT"}', '{ "typ" : "JWT", "other" : 7 }']
    for value in none_variants:
        rejected.extend([
            json.dumps({"alg": value}, separators=(",", ":")),
            json.dumps({"typ": "JWT", "alg": value}, separators=(",", ":")),
            '{ "alg" : ' + json.dumps(value) + ', "typ" : "JWT" }',
        ])

    allowed = [
        '{"alg":"HS256"}',
        '{"typ":"JWT","alg":"RS256"}',
        json.dumps({"other": "none", "alg": random_alg}, separators=(",", ":")),
        json.dumps({"alg": random_alg, "other": "none"}, separators=(",", ":")),
    ]

    for executable in (bin_path, rebuilt):
        for header in rejected:
            _assert_invalid(executable, header)
        for header in allowed:
            _assert_valid(executable, header)


def _decode_b64(data_str):
    """Helper to decode base64/base64url with missing padding."""
    data_str = data_str.replace('-', '+').replace('_', '/')
    pad = len(data_str) % 4
    if pad:
        data_str += '=' * (4 - pad)
    return base64.b64decode(data_str, validate=True)


def test_bad_token_txt():
    """Verify the forged JWT has exactly the requested canonical content."""
    token_path = "/home/user/bad_token.txt"
    assert os.path.isfile(token_path), f"Token file {token_path} is missing."

    with open(token_path, 'r') as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, f"Token must have exactly 3 parts separated by periods. Found {len(parts)} parts."
    assert parts[2] == "", "The signature part (third part) of the token must be empty."

    try:
        header_bytes = _decode_b64(parts[0])
        header = json.loads(header_bytes.decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to decode and parse token header: {e}")

    assert header.get("alg", "").lower() == "none", f"Header 'alg' is {header.get('alg')}, expected 'none'."
    assert header.get("typ") == "JWT", f"Header 'typ' is {header.get('typ')}, expected 'JWT'."

    try:
        payload_bytes = _decode_b64(parts[1])
        payload = json.loads(payload_bytes.decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to decode and parse token payload: {e}")

    assert payload.get("role") == "admin", f"Payload 'role' is {payload.get('role')}, expected 'admin'."

    required_header = b'{"alg":"none","typ":"JWT"}'
    required_payload = b'{"role":"admin"}'
    assert header_bytes == required_header, "JWT header JSON is not exactly the requested content."
    assert payload_bytes == required_payload, "JWT payload JSON is not exactly the requested content."

    expected_header = base64.urlsafe_b64encode(required_header).rstrip(b'=').decode()
    expected_payload = base64.urlsafe_b64encode(required_payload).rstrip(b'=').decode()
    assert token == expected_header + "." + expected_payload + ".", (
        "Token is not the canonical unpadded base64url encoding of the exact requested JSON."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
