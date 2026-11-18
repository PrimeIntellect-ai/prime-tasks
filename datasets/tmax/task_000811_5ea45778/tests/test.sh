#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import datetime
import hashlib
import io
import json
import os
import re
import subprocess
import tarfile

import pytest

INCOMING = "/home/user/incoming_data.b64"
ARCHIVE = "/home/user/archive.tar.gz"
APP_DIR = "/home/user/app_data"
EXPECTED_TOKEN = "cm90YXRlZF9zZWN1cmVfdG9rZW5fOTk5"


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, **kwargs)


def decoded_payload():
    with open(INCOMING, "rb") as f:
        encoded = b"".join(f.read().split())
    return base64.b64decode(encoded, validate=True)


def archive_files():
    payload = decoded_payload()
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
        regular = {
            member.name: archive.extractfile(member).read()
            for member in archive.getmembers()
            if member.isfile()
        }
    assert set(regular) == {"app.py", "allowed_ips.txt"}, \
        f"Unexpected payload members: {sorted(regular)}"
    return regular


def test_payload_decoding_checksum_and_extraction():
    assert os.path.isfile(INCOMING), f"Missing file: {INCOMING}"
    assert os.path.isfile(ARCHIVE), f"Missing file: {ARCHIVE}"

    payload = decoded_payload()
    with open(ARCHIVE, "rb") as f:
        archive_data = f.read()

    assert archive_data == payload, "archive.tar.gz is not the decoded incoming_data.b64 payload"
    assert hashlib.sha256(archive_data).hexdigest() == hashlib.sha256(payload).hexdigest(), \
        "Decoded archive SHA256 checksum does not match the incoming payload"

    files = archive_files()
    allowed_path = os.path.join(APP_DIR, "allowed_ips.txt")
    assert os.path.isfile(allowed_path), f"Missing extracted file: {allowed_path}"
    with open(allowed_path, "rb") as f:
        assert f.read() == files["allowed_ips.txt"], \
            "Extracted allowed_ips.txt does not match the archive"

    app_path = os.path.join(APP_DIR, "app.py")
    assert os.path.isfile(app_path), f"Missing extracted file: {app_path}"


def test_integrity_log():
    """Test that integrity.log exists and contains PASS."""
    log_file = "/home/user/integrity.log"
    assert os.path.exists(log_file), f"Missing file: {log_file}"
    with open(log_file, "r") as f:
        content = f.read().strip()
    assert content == "PASS", f"Expected 'PASS' in {log_file}, got '{content}'"


def test_private_key():
    """Test that new_key.pem is a valid 2048-bit RSA private key."""
    key_file = "/home/user/app_data/new_key.pem"
    assert os.path.exists(key_file), f"Missing file: {key_file}"

    result = run(["openssl", "rsa", "-in", key_file, "-check", "-noout"], text=True)
    assert result.returncode == 0, f"Invalid RSA key in {key_file}: {result.stderr}"

    details = run(["openssl", "pkey", "-in", key_file, "-text", "-noout"], text=True)
    assert details.returncode == 0, details.stderr
    assert re.search(r"Private-Key:\s*\(2048 bit(?:,|\))", details.stdout), \
        "new_key.pem is not an RSA key of exactly 2048 bits"


def test_certificate():
    """Validate the certificate CN, lifetime, self-signature, and key correspondence."""
    cert_file = "/home/user/app_data/new_cert.pem"
    key_file = "/home/user/app_data/new_key.pem"
    assert os.path.exists(cert_file), f"Missing file: {cert_file}"

    result = run(["openssl", "x509", "-in", cert_file, "-noout", "-subject"], text=True)
    assert result.returncode == 0, f"Invalid certificate in {cert_file}: {result.stderr}"
    subject = result.stdout.strip()
    assert "CN = secure.internal" in subject or "CN=secure.internal" in subject, \
        f"Certificate subject does not contain CN=secure.internal. Got: {subject}"

    identity = run([
        "openssl", "x509", "-in", cert_file, "-noout", "-subject", "-issuer",
        "-nameopt", "RFC2253"
    ], text=True)
    assert identity.returncode == 0, identity.stderr
    lines = [line.strip() for line in identity.stdout.splitlines() if line.strip()]
    assert lines == ["subject=CN=secure.internal", "issuer=CN=secure.internal"], \
        f"Certificate must have exactly CN=secure.internal as both subject and issuer: {lines}"

    dates = run(["openssl", "x509", "-in", cert_file, "-noout", "-dates"], text=True)
    assert dates.returncode == 0, dates.stderr
    values = dict(line.split("=", 1) for line in dates.stdout.strip().splitlines())
    not_before = datetime.datetime.strptime(values["notBefore"], "%b %d %H:%M:%S %Y %Z").replace(
        tzinfo=datetime.timezone.utc
    )
    not_after = datetime.datetime.strptime(values["notAfter"], "%b %d %H:%M:%S %Y %Z").replace(
        tzinfo=datetime.timezone.utc
    )
    assert not_after - not_before == datetime.timedelta(days=365), \
        f"Certificate validity is not exactly 365 days: {not_before} to {not_after}"
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now + datetime.timedelta(minutes=5) < not_after, \
        "Certificate is not currently valid"

    verified = run([
        "openssl", "verify", "-check_ss_sig", "-CAfile", cert_file, cert_file
    ], text=True)
    assert verified.returncode == 0, f"Certificate is not validly self-signed: {verified.stderr}"

    key_public = run(["openssl", "pkey", "-in", key_file, "-pubout", "-outform", "DER"])
    assert key_public.returncode == 0, key_public.stderr.decode(errors="replace")
    cert_public_pem = run(["openssl", "x509", "-in", cert_file, "-pubkey", "-noout"])
    assert cert_public_pem.returncode == 0, cert_public_pem.stderr.decode(errors="replace")
    cert_public = run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_public_pem.stdout
    )
    assert cert_public.returncode == 0, cert_public.stderr.decode(errors="replace")
    assert key_public.stdout == cert_public.stdout, \
        "new_cert.pem does not correspond to new_key.pem"


def test_firewall_policy():
    """Test that firewall_policy.json matches the extracted allowed IPs and exact structure."""
    policy_file = "/home/user/firewall_policy.json"
    assert os.path.exists(policy_file), f"Missing file: {policy_file}"

    with open(policy_file, "r") as f:
        try:
            policy = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {policy_file} is not valid JSON")

    source_ips = archive_files()["allowed_ips.txt"].decode("utf-8").splitlines()
    expected_source_ips = ["192.168.1.50", "10.0.0.15", "172.16.20.5"]
    assert source_ips == expected_source_ips, "Unexpected allowed_ips.txt payload"

    expected_policy = {
        "inbound_allow": source_ips,
        "default_action": "deny"
    }
    assert policy == expected_policy, f"Policy JSON does not match expected structure. Got: {policy}"


def test_app_py_credential_rotation():
    """Test that only the hardcoded SECRET_TOKEN value was rotated."""
    app_file = "/home/user/app_data/app.py"
    assert os.path.exists(app_file), f"Missing file: {app_file}"

    with open(app_file, "r") as f:
        content = f.read()

    assert EXPECTED_TOKEN in content, f"Expected base64 token '{EXPECTED_TOKEN}' not found in {app_file}"
    assert f'SECRET_TOKEN = "{EXPECTED_TOKEN}"' in content or \
           f"SECRET_TOKEN = '{EXPECTED_TOKEN}'" in content, \
           "SECRET_TOKEN variable was not updated correctly."

    original = archive_files()["app.py"].decode("utf-8")
    expected_tree = ast.parse(original)
    replacements = 0
    for node in ast.walk(expected_tree):
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == "SECRET_TOKEN"
            for target in node.targets
        ):
            assert isinstance(node.value, ast.Constant) and node.value.value == "legacy_token_A1B2C3"
            node.value = ast.copy_location(ast.Constant(value=EXPECTED_TOKEN), node.value)
            replacements += 1
    assert replacements == 1, "Archive does not contain exactly one expected SECRET_TOKEN assignment"

    try:
        submitted_tree = ast.parse(content)
    except SyntaxError as exc:
        pytest.fail(f"Modified app.py is not valid Python: {exc}")
    assert ast.dump(submitted_tree, include_attributes=False) == ast.dump(expected_tree, include_attributes=False), \
        "app.py differs from the extracted source by more than the required token value rotation"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
