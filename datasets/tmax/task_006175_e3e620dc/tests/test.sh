#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

import pytest

SCRIPT_PATH = "/home/user/recover_evidence.py"
REPORT_PATH = "/home/user/report.txt"
EVIDENCE_PATH = "/home/user/evidence"


def cert_hash(path):
    try:
        der_data = subprocess.check_output(
            ["openssl", "x509", "-in", path, "-outform", "DER"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to process certificate {path}: {e}")
    return hashlib.sha256(der_data).hexdigest()


def expected_report(domain, certificate, payload):
    redacted = re.sub(r"(?<!\\d)(?:\\d{16}|\\d{4}(?:-\\d{4}){3})(?!\\d)", "[REDACTED]", payload)
    return "\n".join([
        f"Rogue Domain: {domain}",
        f"Rogue Cert Hash: {cert_hash(certificate)}",
        f"Redacted Payload: {redacted}",
    ])


def run_submission():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Submitted script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), "Submitted script did not generate /home/user/report.txt"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a regular file."
    with open(REPORT_PATH, "r") as f:
        return f.read().strip()


def test_script_exists():
    """Verify that the user script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."


def test_report_exists():
    """Verify that the generated report exists."""
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist. Did you run your script?"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a regular file."


def test_report_content():
    """Verify the original generated report against the expected derived truth."""
    rogue_cert_path = "/home/user/evidence/certs/rogue.crt"
    assert os.path.exists(rogue_cert_path), f"Rogue certificate {rogue_cert_path} is missing from the environment."

    expected_hash = cert_hash(rogue_cert_path)
    expected_domain = "exfil.evil.net"
    expected_payload = '{"user": "admin", "action": "payment", "cc": "[REDACTED]", "cvv": "123", "secondary_cc": "[REDACTED]"}'
    expected_content = "\n".join([
        f"Rogue Domain: {expected_domain}",
        f"Rogue Cert Hash: {expected_hash}",
        f"Redacted Payload: {expected_payload}",
    ])

    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"Report content at {REPORT_PATH} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )


def test_script_generates_original_report():
    """Actually execute the submission against the original evidence."""
    certificate = "/home/user/evidence/certs/rogue.crt"
    payload = '{"user": "admin", "action": "payment", "cc": "4111-2222-3333-4444", "cvv": "123", "secondary_cc": "1111222233334444"}'
    expected = expected_report("exfil.evil.net", certificate, payload)
    assert run_submission() == expected


def test_script_handles_altered_evidence():
    """Exercise parsing, CN matching, DER hashing, and redaction on fresh evidence."""
    backup_root = tempfile.mkdtemp(prefix="evidence-backup-")
    backup_evidence = os.path.join(backup_root, "evidence")
    shutil.copytree(EVIDENCE_PATH, backup_evidence)

    token = secrets.token_hex(8)
    domain = f"collector-{token}.invalid"
    cert_name = f"capture-{secrets.token_hex(4)}.pem"
    decoy_name = f"decoy-{secrets.token_hex(4)}.crt"
    cert_dir = os.path.join(EVIDENCE_PATH, "certs")
    rogue_cert = os.path.join(cert_dir, cert_name)
    rogue_key = os.path.join(backup_root, "rogue.key")
    decoy_key = os.path.join(backup_root, "decoy.key")

    benign_payload = '{"user":"guest","cc":"9999888877776666"}'
    malicious_payload = '{"case":"' + token + '","primary":"9876543210123456","secondary":"1234-5678-9012-3456","keep":"123-45-6789"}'

    try:
        shutil.rmtree(EVIDENCE_PATH)
        os.makedirs(cert_dir)

        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", rogue_key, "-out", rogue_cert, "-days", "2", "-nodes",
            "-subj", f"/CN={domain}",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)

        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", decoy_key, "-out", os.path.join(cert_dir, decoy_name),
            "-days", "2", "-nodes", "-subj", "/CN=unrelated.invalid",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)

        with open(os.path.join(EVIDENCE_PATH, "server.log"), "w") as f:
            f.write("[INFO] GET /safe\n")
            f.write("[INFO] Header: Content-Security-Policy: default-src 'self';\n")
            f.write(f"[INFO] Payload: {benign_payload}\n")
            f.write("[INFO] GET /sensitive\n")
            f.write("[INFO] Header: Content-Security-Policy: default-src 'self'; report-uri https://" + domain + "/receive\n")
            f.write(f"[INFO] Payload: {malicious_payload}\n")

        expected = expected_report(domain, rogue_cert, malicious_payload)
        actual = run_submission()
        assert actual == expected, (
            "Script output was incorrect for altered evidence.\n"
            f"Expected:\n{expected}\n\nGot:\n{actual}"
        )
    finally:
        if os.path.exists(EVIDENCE_PATH):
            shutil.rmtree(EVIDENCE_PATH)
        shutil.copytree(backup_evidence, EVIDENCE_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
