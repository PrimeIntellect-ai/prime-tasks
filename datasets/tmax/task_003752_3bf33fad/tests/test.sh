#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import hashlib
import zipfile
import io
from cryptography import x509
from cryptography.x509.oid import NameOID

def test_craft_script_runs_and_generates_payload():
    """Ensure the craft script exists, runs successfully, and generates the payload."""
    script_path = "/home/user/craft.py"
    payload_path = "/home/user/payload.zip"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    # Remove payload.zip if it exists to ensure the script actually generates it
    if os.path.exists(payload_path):
        os.remove(payload_path)

    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to run. stderr:\n{result.stderr}"
    assert os.path.isfile(payload_path), f"Script did not generate {payload_path}"

def test_payload_zip_custom_hash():
    """Verify the payload has the correct SHA-256 hash appended at the end."""
    payload_path = "/home/user/payload.zip"
    assert os.path.isfile(payload_path), f"Payload file {payload_path} does not exist."

    with open(payload_path, "rb") as f:
        data = f.read()

    assert len(data) > 64, "Payload file is too small to contain a 64-byte hash."

    file_data = data[:-64]
    hash_hex = data[-64:].decode('ascii', errors='ignore')

    expected_hash = hashlib.sha256(file_data).hexdigest()
    assert hash_hex == expected_hash, f"Hash mismatch. Expected {expected_hash}, got {hash_hex}"

def test_payload_zip_contents_and_cert():
    """Verify the ZIP contains the correct path traversal file and a valid certificate."""
    payload_path = "/home/user/payload.zip"
    with open(payload_path, "rb") as f:
        data = f.read()

    assert len(data) > 64, "Payload file too small."
    file_data = data[:-64]

    try:
        zf = zipfile.ZipFile(io.BytesIO(file_data))
    except zipfile.BadZipFile:
        assert False, "The file data (excluding the last 64 bytes) is not a valid ZIP archive."

    names = zf.namelist()

    # Verify path traversal payload
    expected_path = "../../../home/user/success.txt"
    assert expected_path in names, f"Path traversal file '{expected_path}' not found in ZIP directory structure."

    content = zf.read(expected_path)
    assert content == b"EXPLOIT_WORKED", f"Content of '{expected_path}' is incorrect."

    # Verify dummy certificate
    assert "cert.pem" in names, "'cert.pem' not found in ZIP archive."
    cert_data = zf.read("cert.pem")

    cert_path = "/tmp/test_cert.pem"
    with open(cert_path, "wb") as f:
        f.write(cert_data)

    # Check certificate validity and Common Name using openssl
    res = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject"],
        capture_output=True,
        text=True
    )
    assert res.returncode == 0, f"openssl failed to parse the certificate. stderr:\n{res.stderr}"
    assert "vulnerable.local" in res.stdout, f"Certificate Common Name (CN) does not contain 'vulnerable.local'. Subject: {res.stdout}"

    # Parse the subject structurally so another subject field cannot satisfy the CN check.
    cert = x509.load_pem_x509_certificate(cert_data)
    common_names = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    assert len(common_names) == 1, f"Certificate must have exactly one Common Name; found {len(common_names)}."
    assert common_names[0].value == "vulnerable.local", \
        f"Certificate Common Name must be exactly 'vulnerable.local', got {common_names[0].value!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
