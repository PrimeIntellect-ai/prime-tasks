#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import pytest

REPORT_FILE = "/home/user/policy_report.json"
SCRIPT_FILE = "/home/user/policy_check.py"
BUNDLE_DIR = "/home/user/release_bundle"
REQUIREMENTS_FILE = os.path.join(BUNDLE_DIR, "requirements.txt")
TRAFFIC_FILE = os.path.join(BUNDLE_DIR, "traffic.log")
SERVER_CERT = os.path.join(BUNDLE_DIR, "server.crt")
CA_CERT = os.path.join(BUNDLE_DIR, "ca.crt")
EXPECTED_KEYS = {
    "vulnerable_dependency_found",
    "intrusion_detected",
    "certificate_valid",
}


def test_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"The script {SCRIPT_FILE} does not exist. Did you create it?"


def test_report_file_exists():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist. Did you run your script?"


def test_report_file_content():
    try:
        with open(REPORT_FILE, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {REPORT_FILE}: {e}")

    expected_keys = {"vulnerable_dependency_found", "intrusion_detected", "certificate_valid"}
    assert set(data.keys()) == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, got {set(data.keys())}"

    assert data["vulnerable_dependency_found"] is True, "Expected 'vulnerable_dependency_found' to be True based on the requirements.txt"
    assert data["intrusion_detected"] is True, "Expected 'intrusion_detected' to be True based on the traffic.log"
    assert data["certificate_valid"] is True, "Expected 'certificate_valid' to be True based on the valid certificate chain"


def independently_expected():
    vulnerable = False
    with open(REQUIREMENTS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            name, separator, version = line.strip().partition("==")
            if separator and name.strip() == "requests":
                parts = tuple(int(part) for part in version.strip().split("."))
                vulnerable = parts < (2, 31, 0)
                break

    with open(TRAFFIC_FILE, "r", encoding="utf-8") as f:
        intrusion = any(
            re.search(r"(UNION.*SELECT|OR\s+'1'='1'|\/etc\/passwd)", line, re.IGNORECASE)
            for line in f
        )

    certificate_valid = subprocess.run(
        ["openssl", "verify", "-CAfile", CA_CERT, SERVER_CERT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0

    return {
        "vulnerable_dependency_found": vulnerable,
        "intrusion_detected": intrusion,
        "certificate_valid": certificate_valid,
    }


def execute_and_read_report():
    if os.path.exists(REPORT_FILE):
        os.unlink(REPORT_FILE)

    result = subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"policy_check.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(REPORT_FILE), "Running policy_check.py did not generate policy_report.json"

    try:
        with open(REPORT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        pytest.fail(f"Generated report is not valid JSON: {exc}")

    assert isinstance(data, dict), "Generated report must be a JSON object"
    assert set(data.keys()) == EXPECTED_KEYS, f"JSON keys mismatch: {set(data.keys())}"
    assert all(type(data[key]) is bool for key in EXPECTED_KEYS), "All report values must be booleans"
    return data


def test_script_actually_analyzes_bundle():
    paths = [REQUIREMENTS_FILE, TRAFFIC_FILE, SERVER_CERT, CA_CERT]
    originals = {path: open(path, "rb").read() for path in paths}
    original_report = open(REPORT_FILE, "rb").read() if os.path.isfile(REPORT_FILE) else None

    with tempfile.TemporaryDirectory() as temp_dir:
        invalid_cert = os.path.join(temp_dir, "untrusted.crt")
        invalid_key = os.path.join(temp_dir, "untrusted.key")
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-days", "2", "-subj", "/CN=Untrusted Test Certificate",
                "-keyout", invalid_key, "-out", invalid_cert,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        invalid_cert_bytes = open(invalid_cert, "rb").read()

        try:
            # Re-run against the supplied bundle rather than trusting the pre-generated report.
            expected = independently_expected()
            assert execute_and_read_report() == expected

            cases = [
                (
                    b"Flask==2.2.3\nrequests==2.31.0\n",
                    b"127.0.0.1 - benign request\n",
                    originals[SERVER_CERT],
                ),
                (
                    b"requests==2.30.9\nWerkzeug==2.2.3\n",
                    b"GET /search?q=uNiOn%20anything%20SeLeCt HTTP/1.1\n",
                    invalid_cert_bytes,
                ),
                (
                    b"requests==2.31.0\n",
                    b"GET /download?file=/EtC/PaSsWd HTTP/1.1\n",
                    originals[SERVER_CERT],
                ),
            ]

            for requirements, traffic, server_cert in cases:
                with open(REQUIREMENTS_FILE, "wb") as f:
                    f.write(requirements)
                with open(TRAFFIC_FILE, "wb") as f:
                    f.write(traffic)
                with open(SERVER_CERT, "wb") as f:
                    f.write(server_cert)

                expected = independently_expected()
                actual = execute_and_read_report()
                assert actual == expected, f"Expected {expected}, got {actual}"
        finally:
            for path, content in originals.items():
                with open(path, "wb") as f:
                    f.write(content)
            if original_report is None:
                if os.path.exists(REPORT_FILE):
                    os.unlink(REPORT_FILE)
            else:
                with open(REPORT_FILE, "wb") as f:
                    f.write(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
