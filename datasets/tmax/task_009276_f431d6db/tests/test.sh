#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess
import pytest

def test_report_exists():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"Missing report file: {path} is not found."

def test_report_contents():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"Cannot test contents, missing {path}"

    with open(path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert "tampered_line_number" in report, "Key 'tampered_line_number' is missing from the report."
    assert "tampered_ip" in report, "Key 'tampered_ip' is missing from the report."
    assert "cert_fingerprint" in report, "Key 'cert_fingerprint' is missing from the report."

    assert report["tampered_line_number"] == 4, f"Incorrect tampered_line_number. Expected 4, got {report['tampered_line_number']}."
    assert report["tampered_ip"] == "203.0.113.5", f"Incorrect tampered_ip. Expected '203.0.113.5', got '{report['tampered_ip']}'."

    cert_path = "/home/user/cert.pem"
    assert os.path.isfile(cert_path), f"Missing certificate file: {cert_path} is required to compute the fingerprint."

    try:
        out = subprocess.check_output(
            ["openssl", "x509", "-in", cert_path, "-noout", "-fingerprint", "-sha256"],
            stderr=subprocess.STDOUT
        ).decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read certificate fingerprint using openssl: {e.output.decode('utf-8')}")

    # The output format is typically "sha256 Fingerprint=XX:XX:XX..."
    if "=" in out:
        expected_fp = out.split("=", 1)[1].strip()
    else:
        pytest.fail(f"Unexpected openssl output format: {out}")

    assert report["cert_fingerprint"] == expected_fp, f"Incorrect cert_fingerprint. Expected '{expected_fp}', got '{report['cert_fingerprint']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
