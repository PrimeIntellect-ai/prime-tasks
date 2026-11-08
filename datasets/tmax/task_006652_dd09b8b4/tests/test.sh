#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import shutil
import stat
import subprocess
import pytest

JWT_FILE = "/home/user/forged_payload.jwt"
SCRIPT_FILE = "/home/user/generate_payload.py"
KEYSTORE_FILE = "/home/user/server_keystore.p12"
KEYSTORE_PASS = "redteam123"


def b64url_decode(data):
    rem = len(data) % 4
    if rem > 0:
        data += '=' * (4 - rem)
    return base64.urlsafe_b64decode(data)


def test_files_exist():
    """Test that the required output files exist."""
    assert os.path.isfile(JWT_FILE), f"Missing required file: {JWT_FILE}"
    assert os.path.isfile(SCRIPT_FILE), f"Missing required file: {SCRIPT_FILE}"


def test_jwt_content_and_signature(tmp_path):
    """Test that the JWT has the correct header, payload, and a valid signature."""
    assert os.path.isfile(JWT_FILE), f"JWT file not found: {JWT_FILE}"

    with open(JWT_FILE, "r") as f:
        token = f.read().strip()

    parts = token.split(".")
    assert len(parts) == 3, "JWT must contain exactly 3 parts (header, payload, signature)"

    header_b64, payload_b64, sig_b64 = parts

    # Check header
    try:
        header = json.loads(b64url_decode(header_b64).decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT header: {e}")

    assert header.get("alg") == "RS256", f"Expected alg RS256, got {header.get('alg')}"
    assert header.get("kid") == "internal-ca-01", f"Expected kid internal-ca-01, got {header.get('kid')}"

    # Check payload
    try:
        payload = json.loads(b64url_decode(payload_b64).decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT payload: {e}")

    assert payload.get("role") == "admin", f"Expected role 'admin', got {payload.get('role')}"
    expected_username = "admin'/**/UNION/**/SELECT/**/1,2,3--"
    assert payload.get("username") == expected_username, f"Expected username {expected_username}, got {payload.get('username')}"

    # Verify signature
    pubkey_path = tmp_path / "pubkey.pem"
    try:
        cmd = f"openssl pkcs12 -in {KEYSTORE_FILE} -clcerts -nokeys -passin pass:{KEYSTORE_PASS} | openssl x509 -pubkey -noout"
        pubkey = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL)
        pubkey_path.write_bytes(pubkey)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to extract public key from keystore")

    sig_bytes = b64url_decode(sig_b64)
    sig_path = tmp_path / "sig.bin"
    sig_path.write_bytes(sig_bytes)

    data_path = tmp_path / "data.bin"
    data_path.write_bytes(f"{header_b64}.{payload_b64}".encode('utf-8'))

    try:
        subprocess.check_call(
            ["openssl", "dgst", "-sha256", "-verify", str(pubkey_path), "-signature", str(sig_path), str(data_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        pytest.fail("JWT signature verification failed. The token was not correctly signed with the keystore's private key.")


def test_generation_script_fully_automates_process(tmp_path):
    """Execute the script against a fresh keystore and verify its generated JWT."""
    assert os.path.isfile(SCRIPT_FILE), f"Missing required file: {SCRIPT_FILE}"

    fresh_key = tmp_path / "fresh_private.pem"
    fresh_cert = tmp_path / "fresh_cert.pem"
    fresh_keystore = tmp_path / "fresh_keystore.p12"

    subprocess.check_call(
        [
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", str(fresh_key), "-out", str(fresh_cert),
            "-days", "1", "-nodes", "-subj", "/CN=internal-ca-01"
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    subprocess.check_call(
        [
            "openssl", "pkcs12", "-export", "-out", str(fresh_keystore),
            "-inkey", str(fresh_key), "-in", str(fresh_cert),
            "-passout", f"pass:{KEYSTORE_PASS}"
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    original_keystore = open(KEYSTORE_FILE, "rb").read()
    original_mode = stat.S_IMODE(os.stat(KEYSTORE_FILE).st_mode)
    original_jwt = open(JWT_FILE, "rb").read() if os.path.isfile(JWT_FILE) else None

    try:
        shutil.copyfile(fresh_keystore, KEYSTORE_FILE)
        os.chmod(KEYSTORE_FILE, original_mode)
        if os.path.exists(JWT_FILE):
            os.remove(JWT_FILE)

        result = subprocess.run(
            ["python3", SCRIPT_FILE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60
        )
        assert result.returncode == 0, (
            f"generate_payload.py failed with exit code {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(JWT_FILE), "generate_payload.py did not create forged_payload.jwt"

        validation_dir = tmp_path / "generated_validation"
        validation_dir.mkdir()
        test_jwt_content_and_signature(validation_dir)
    finally:
        with open(KEYSTORE_FILE, "wb") as f:
            f.write(original_keystore)
        os.chmod(KEYSTORE_FILE, original_mode)
        if original_jwt is None:
            if os.path.exists(JWT_FILE):
                os.remove(JWT_FILE)
        else:
            with open(JWT_FILE, "wb") as f:
                f.write(original_jwt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
