#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import pytest

REPORT_PATH = "/home/user/report.json"
ROOT_PATH = "/home/user/extracted_root.pem"
TRAFFIC_CERTS_PATH = "/home/user/traffic_certs.pem"
CLIENT_BIN_PATH = "/home/user/client_bin"

CERT_RE = re.compile(
    rb"-----BEGIN CERTIFICATE-----\r?\n.*?-----END CERTIFICATE-----\r?\n?",
    re.DOTALL,
)


def certs_in(path):
    with open(path, "rb") as f:
        return CERT_RE.findall(f.read())


def cert_der(path):
    return subprocess.check_output(
        ["openssl", "x509", "-in", path, "-outform", "DER"],
        stderr=subprocess.STDOUT,
    )


def test_extracted_root_exists():
    """Test that extracted_root.pem exists and is one valid certificate."""
    assert os.path.exists(ROOT_PATH), f"Missing file: {ROOT_PATH}"
    assert os.path.isfile(ROOT_PATH), f"Not a file: {ROOT_PATH}"
    assert len(certs_in(ROOT_PATH)) == 1, f"{ROOT_PATH} must contain exactly one PEM certificate"

    try:
        subprocess.check_output(
            ["openssl", "x509", "-in", ROOT_PATH, "-noout"],
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"{ROOT_PATH} is not a valid x509 certificate. OpenSSL error: {e.output.decode()}")


def test_extracted_root_matches_certificate_embedded_in_client():
    """Verify that the submitted root is the certificate embedded in client_bin."""
    assert os.path.isfile(CLIENT_BIN_PATH), f"Missing file: {CLIENT_BIN_PATH}"
    embedded = certs_in(CLIENT_BIN_PATH)
    assert len(embedded) == 1, "client_bin must contain exactly one embedded PEM certificate"

    with tempfile.NamedTemporaryFile(suffix=".pem") as embedded_file:
        embedded_file.write(embedded[0])
        embedded_file.flush()
        try:
            embedded_der = cert_der(embedded_file.name)
            submitted_der = cert_der(ROOT_PATH)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Could not parse embedded or extracted certificate: {e.output.decode()}")

    assert submitted_der == embedded_der, "extracted_root.pem is not the certificate embedded in client_bin"


def test_report_json_exists_and_valid():
    """Test that report.json exists and is valid JSON."""
    assert os.path.exists(REPORT_PATH), f"Missing file: {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Not a file: {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} does not contain valid JSON.")


def test_report_contents():
    """Test that report.json contains the correct metadata and chain result."""
    with open(REPORT_PATH, "r") as f:
        report = json.load(f)

    try:
        real_root_subj = subprocess.check_output(
            ["openssl", "x509", "-in", ROOT_PATH, "-subject", "-noout"]
        ).decode().strip()
    except subprocess.CalledProcessError:
        pytest.fail(f"Could not read subject from {ROOT_PATH}")

    assert "root_ca_subject" in report, "Missing 'root_ca_subject' in report.json"
    assert report["root_ca_subject"] == real_root_subj, f"Mismatch in root_ca_subject. Expected: {real_root_subj}"

    real_leaf_cn = "target.evilcorp.local"
    assert "leaf_cn" in report, "Missing 'leaf_cn' in report.json"
    assert report["leaf_cn"] == real_leaf_cn, f"Mismatch in leaf_cn. Expected: {real_leaf_cn}"

    try:
        cmd = ["openssl", "x509", "-in", TRAFFIC_CERTS_PATH, "-serial", "-noout"]
        serial_output = subprocess.check_output(cmd).decode().strip()
        real_serial = serial_output.split("=", 1)[1].upper()
    except Exception as e:
        pytest.fail(f"Could not read serial from {TRAFFIC_CERTS_PATH}: {e}")

    assert "leaf_serial" in report, "Missing 'leaf_serial' in report.json"
    assert report["leaf_serial"] == real_serial, f"Mismatch in leaf_serial. Expected: {real_serial}"

    traffic_certs = certs_in(TRAFFIC_CERTS_PATH)
    assert len(traffic_certs) == 2, "traffic_certs.pem must contain the leaf followed by one intermediate"

    with tempfile.TemporaryDirectory() as td:
        leaf_path = os.path.join(td, "leaf.pem")
        intermediate_path = os.path.join(td, "intermediate.pem")
        with open(leaf_path, "wb") as f:
            f.write(traffic_certs[0])
        with open(intermediate_path, "wb") as f:
            f.write(traffic_certs[1])

        verify_result = subprocess.run(
            [
                "openssl", "verify",
                "-CAfile", ROOT_PATH,
                "-untrusted", intermediate_path,
                leaf_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

    actual_chain_valid = verify_result.returncode == 0
    assert actual_chain_valid, f"Certificate chain verification failed: {verify_result.stdout}"
    assert "chain_valid" in report, "Missing 'chain_valid' in report.json"
    assert report["chain_valid"] is True, "chain_valid should be true"
    assert report["chain_valid"] == actual_chain_valid, "chain_valid does not match openssl verification"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
