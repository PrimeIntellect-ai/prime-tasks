#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import os
import secrets
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
SCRIPT_PATH = "/home/user/c2_ingress"
CA_CERT = "/app/ca.pem"
CA_KEY = "/app/ca.key"
SECRET = b"R3dT3am!2024"


def run_script(payload_path):
    return subprocess.run(
        [SCRIPT_PATH, str(payload_path)],
        capture_output=True,
        timeout=10,
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory {CLEAN_DIR} is missing."
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory {EVIL_DIR} is missing."

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for clean_file in clean_files:
        result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(clean_file))

    evil_failures = []
    for evil_file in evil_files:
        result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(evil_file))

    error_msg = ""
    if clean_failures:
        error_msg += f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}. "
    if evil_failures:
        error_msg += f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}."

    assert not clean_failures and not evil_failures, error_msg.strip()


def openssl(*args, check=True):
    return subprocess.run(
        ["openssl", *map(str, args)],
        check=check,
        capture_output=True,
        timeout=20,
    )


def make_ca_signed_cert(workdir, label):
    key = workdir / f"{label}.key"
    csr = workdir / f"{label}.csr"
    cert = workdir / f"{label}.pem"
    serial = workdir / f"{label}.srl"
    openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
            "-out", csr, "-subj", f"/CN={label}-{uuid.uuid4().hex}")
    openssl("x509", "-req", "-in", csr, "-CA", CA_CERT, "-CAkey", CA_KEY,
            "-CAcreateserial", "-CAserial", serial, "-out", cert, "-days", "30")
    verification = openssl("verify", "-CAfile", CA_CERT, cert, check=False)
    assert verification.returncode == 0, verification.stderr.decode(errors="replace")
    return cert.read_bytes()


def make_self_signed_cert(workdir, label):
    key = workdir / f"{label}.key"
    cert = workdir / f"{label}.pem"
    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
            "-out", cert, "-days", "30", "-subj", f"/CN={label}-{uuid.uuid4().hex}")
    verification = openssl("verify", "-CAfile", CA_CERT, cert, check=False)
    assert verification.returncode != 0, "Fresh self-signed certificate unexpectedly verifies under the Root CA"
    return cert.read_bytes()


def encode_payload(cert_bytes, command, mac=None):
    if mac is None:
        mac = hmac.new(SECRET, command.encode(), hashlib.sha256).hexdigest()
    cert_field = base64.b64encode(cert_bytes).decode()
    decoded = f"{cert_field}|{mac}|{command}".encode()
    return base64.b64encode(decoded)


def test_fresh_cryptographic_payloads():
    assert os.path.isfile(CA_CERT), f"Root CA {CA_CERT} is missing."
    assert os.path.isfile(CA_KEY), "Verifier cannot generate fresh CA-signed certificates."

    with tempfile.TemporaryDirectory(prefix="c2_verify_") as td:
        workdir = Path(td)
        valid_certs = [make_ca_signed_cert(workdir, f"client{i}") for i in range(3)]
        rogue_cert = make_self_signed_cert(workdir, "rogue")

        commands = [
            f"id_{secrets.token_hex(12)}",
            f"hostname_{secrets.token_hex(12)}",
            f"collect-{secrets.token_hex(16)}",
        ]

        cases = []
        for cert, command in zip(valid_certs, commands):
            cases.append((encode_payload(cert, command), True))

        bad_mac_command = f"status_{secrets.token_hex(12)}"
        cases.append((encode_payload(valid_certs[0], bad_mac_command, "0" * 64), False))

        altered_command = f"exec_{secrets.token_hex(12)}"
        mac_for_other_command = hmac.new(
            SECRET, (altered_command + "_different").encode(), hashlib.sha256
        ).hexdigest()
        cases.append((encode_payload(valid_certs[1], altered_command, mac_for_other_command), False))

        rogue_command = f"probe_{secrets.token_hex(12)}"
        cases.append((encode_payload(rogue_cert, rogue_command), False))

        invalid_cert_command = f"invalidcert_{secrets.token_hex(12)}"
        cases.append((encode_payload(os.urandom(192), invalid_cert_command), False))

        cases.append((b"invalid_base64_!@#_" + secrets.token_hex(8).encode(), False))
        cases.append((base64.b64encode(f"only|two-{secrets.token_hex(8)}".encode()), False))

        # Randomize invocation order and use opaque filenames in one common directory,
        # so expected classifications cannot be inferred from paths or call order.
        secrets.SystemRandom().shuffle(cases)
        failures = []
        for payload, should_accept in cases:
            path = workdir / uuid.uuid4().hex
            path.write_bytes(payload)
            result = run_script(path)
            accepted = result.returncode == 0
            if accepted != should_accept:
                failures.append(
                    f"{path.name}: expected {'accept' if should_accept else 'reject'}, "
                    f"got exit status {result.returncode}"
                )

        assert not failures, "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
