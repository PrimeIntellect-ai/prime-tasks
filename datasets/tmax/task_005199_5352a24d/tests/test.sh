#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import re
import stat
import subprocess

import pytest
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

SERVICE_PATH = "/home/user/secure_service/verify_and_run.py"
TRUST_PATH = "/home/user/secure_service/certs/trust.pem"
PAYLOAD_PATH = "/home/user/payload.json"
OUTPUT_PATH = "/home/user/final_output.txt"
EXPECTED_HASH = hashlib.sha256(b"Pwned_By_Auditor").hexdigest()
EXPECTED_OUTPUT = f"EXPLOIT_SUCCESS: {EXPECTED_HASH}\n"

EXPECTED_SERVICE = b'''import sys
import json
import base64
from cryptography.x509 import load_pem_x509_certificates
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes
from cryptography.exceptions import InvalidSignature

if len(sys.argv) != 2:
    print("Usage: python verify_and_run.py <payload.json>")
    sys.exit(1)

try:
    with open(sys.argv[1], 'r') as f:
        payload = json.load(f)

    code_b64 = payload['code']
    signature = base64.b64decode(payload['signature'])
    code_bytes = base64.b64decode(code_b64)

    with open('/home/user/secure_service/certs/trust.pem', 'rb') as f:
        trust_pem = f.read()

    certs = load_pem_x509_certificates(trust_pem)

    verified = False
    for cert in certs:
        public_key = cert.public_key()
        try:
            public_key.verify(
                signature,
                code_b64.encode('utf-8'),
                padding.PKCS1v15(),
                hashes.SHA256()
            )
            verified = True
            break
        except InvalidSignature:
            continue

    if not verified:
        print("Verification failed.")
        sys.exit(1)

    # Execute the sandboxed code
    exec(code_bytes.decode('utf-8'))

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
'''


def read_payload():
    assert os.path.exists(PAYLOAD_PATH), f"File {PAYLOAD_PATH} does not exist. Did you create the payload?"
    assert os.path.isfile(PAYLOAD_PATH), f"Path {PAYLOAD_PATH} is not a regular file."
    try:
        with open(PAYLOAD_PATH, "r") as f:
            payload = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {PAYLOAD_PATH} does not contain valid JSON.")

    assert isinstance(payload, dict), f"JSON root in {PAYLOAD_PATH} must be an object/dictionary."
    assert "code" in payload, f"'code' key missing from {PAYLOAD_PATH}."
    assert "signature" in payload, f"'signature' key missing from {PAYLOAD_PATH}."
    assert set(payload) == {"code", "signature"}, "payload.json must contain exactly the code and signature fields."
    assert isinstance(payload["code"], str), "'code' must be a string."
    assert isinstance(payload["signature"], str), "'signature' must be a string."
    return payload


def load_trust():
    assert os.path.isfile(TRUST_PATH), f"Missing certificate store {TRUST_PATH}."
    trust_pem = open(TRUST_PATH, "rb").read()
    certs = x509.load_pem_x509_certificates(trust_pem)
    assert len(certs) >= 2, "The certificate store must retain the legitimate certificate and have a certificate appended."

    original_pem = certs[0].public_bytes(serialization.Encoding.PEM)
    assert trust_pem.startswith(original_pem), "The original certificate was not retained at the start of trust.pem."
    assert certs[0].serial_number == 1, "The original legitimate certificate was replaced."
    common_names = certs[0].subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    assert len(common_names) == 1 and common_names[0].value == "LegitService", "The original legitimate certificate was replaced."
    return trust_pem, certs, original_pem


def test_vulnerable_files_log():
    log_path = "/home/user/vulnerable_files.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist. Did you run the permission audit?"
    assert os.path.isfile(log_path), f"Path {log_path} is not a regular file."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # chmod -R 777 made both pre-existing service files world-writable.
    assert len(lines) == 2, f"Expected exactly two world-writable service files in the audit, but found {len(lines)}."
    findings = {}
    for line in lines:
        match = re.fullmatch(r"(/home/user/secure_service/(?:verify_and_run\.py|certs/trust\.pem))\s+([a-f0-9]{64})", line)
        assert match is not None, f"Line in {log_path} is incorrectly formatted or names an unexpected file: {line}"
        assert match.group(1) not in findings, f"Duplicate audit entry for {match.group(1)}."
        findings[match.group(1)] = match.group(2)

    assert set(findings) == {SERVICE_PATH, TRUST_PATH}
    for path in findings:
        assert os.stat(path).st_mode & stat.S_IWOTH, f"Audited path is not world-writable: {path}"

    assert open(SERVICE_PATH, "rb").read() == EXPECTED_SERVICE, "verify_and_run.py was modified."
    assert findings[SERVICE_PATH] == hashlib.sha256(EXPECTED_SERVICE).hexdigest(), "Incorrect SHA256 for verify_and_run.py."

    _, _, original_pem = load_trust()
    assert findings[TRUST_PATH] == hashlib.sha256(original_pem).hexdigest(), "The trust.pem audit hash is not the hash from before the certificate was appended."


def test_payload_json_and_signature():
    payload = read_payload()
    try:
        code_bytes = base64.b64decode(payload["code"], validate=True)
        signature = base64.b64decode(payload["signature"], validate=True)
        code_bytes.decode("utf-8")
    except (ValueError, UnicodeDecodeError) as exc:
        pytest.fail(f"Payload contains invalid base64 or non-UTF-8 code: {exc}")

    _, certs, _ = load_trust()
    signing_cert = None
    for cert in certs[1:]:
        public_key = cert.public_key()
        if not isinstance(public_key, rsa.RSAPublicKey) or public_key.key_size != 2048:
            continue
        try:
            public_key.verify(
                signature,
                payload["code"].encode("utf-8"),
                padding.PKCS1v15(),
                hashes.SHA256(),
            )
            signing_cert = cert
            break
        except InvalidSignature:
            pass

    assert signing_cert is not None, "No appended 2048-bit RSA certificate validates the payload signature with PKCS1v15/SHA256."
    assert signing_cert.subject == signing_cert.issuer, "The appended signing certificate is not self-signed."
    signing_key = signing_cert.public_key()
    try:
        signing_key.verify(
            signing_cert.signature,
            signing_cert.tbs_certificate_bytes,
            padding.PKCS1v15(),
            signing_cert.signature_hash_algorithm,
        )
    except InvalidSignature:
        pytest.fail("The appended certificate's self-signature is invalid.")


def test_final_output_txt_and_service_execution():
    assert os.path.exists(OUTPUT_PATH), f"File {OUTPUT_PATH} does not exist. Did you execute the service?"
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a regular file."
    with open(OUTPUT_PATH, "r") as f:
        content = f.read()

    expected_string = EXPECTED_OUTPUT.rstrip("\n")
    assert expected_string in content, f"Expected string '{expected_string}' not found in {OUTPUT_PATH}. Execution may have failed or payload was incorrect."
    assert content == EXPECTED_OUTPUT, f"{OUTPUT_PATH} must contain exactly the payload's required output."

    assert open(SERVICE_PATH, "rb").read() == EXPECTED_SERVICE, "verify_and_run.py was modified."
    result = subprocess.run(
        ["python3", SERVICE_PATH, PAYLOAD_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"The real service rejected or failed to run payload.json: {result.stdout}{result.stderr}"
    assert result.stdout == EXPECTED_OUTPUT, "Executing payload.json through verify_and_run.py did not produce exactly the required output."
    assert open(SERVICE_PATH, "rb").read() == EXPECTED_SERVICE, "verify_and_run.py was modified during payload execution."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
