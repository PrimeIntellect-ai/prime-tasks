#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/generate_audit.sh")
REPORT_PATH = Path("/home/user/audit_report.json")
CERT_PATH = Path("/home/user/certs/server.crt")
CA_PATH = Path("/home/user/certs/ca.crt")
WAF_PATH = Path("/home/user/logs/waf.log")


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert SCRIPT_PATH.is_file(), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    REPORT_PATH.unlink(missing_ok=True)
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert REPORT_PATH.is_file(), "Script did not create /home/user/audit_report.json."


def test_script_exists_and_executable():
    script_path = "/home/user/generate_audit.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_audit_report_exists():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Report {report_path} does not exist."


def test_audit_report_content():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Report {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "certificate_valid" in report, "Key 'certificate_valid' missing from JSON."
    assert report["certificate_valid"] is True, "certificate_valid should be true."

    assert "server_cert_subject" in report, "Key 'server_cert_subject' missing from JSON."
    expected_subject = "CN = secure.internal.corp"
    actual_subject = report["server_cert_subject"].strip()
    if actual_subject.startswith("subject="):
        actual_subject = actual_subject[len("subject="):].strip()
    assert actual_subject == expected_subject, f"Expected subject '{expected_subject}', got '{report['server_cert_subject']}'"

    assert "threat_ips" in report, "Key 'threat_ips' missing from JSON."
    expected_ips = ["192.168.1.100", "192.168.1.50"]
    actual_ips = report["threat_ips"]
    assert isinstance(actual_ips, list), "threat_ips should be a list."
    assert sorted(actual_ips) == sorted(expected_ips), f"Expected threat_ips {expected_ips}, got {actual_ips}"

    # Check if sorted in ascending order as requested
    assert actual_ips == sorted(actual_ips), "threat_ips are not sorted in ascending order."


def test_script_uses_current_certificate_and_log_inputs(tmp_path):
    original_cert = CERT_PATH.read_bytes()
    original_log = WAF_PATH.read_bytes()
    original_report = REPORT_PATH.read_bytes()
    cert_mode = CERT_PATH.stat().st_mode
    log_mode = WAF_PATH.stat().st_mode

    try:
        token = secrets.token_hex(6)
        dynamic_cert = tmp_path / "dynamic.crt"
        dynamic_key = tmp_path / "dynamic.key"
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(dynamic_key), "-out", str(dynamic_cert),
                "-days", "2", "-subj", f"/CN=audit-{token}.internal",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        CERT_PATH.write_bytes(dynamic_cert.read_bytes())

        ips = set()
        while len(ips) < 5:
            ips.add(f"10.{secrets.randbelow(250) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}")
        both_one, both_two, sqli_only, xss_only, unrelated = list(ips)
        records = [
            ("SQLI", both_one),
            ("XSS", both_one),
            ("XSS", both_two),
            ("SQLI", both_two),
            ("SQLI", both_two),
            ("SQLI", sqli_only),
            ("XSS", xss_only),
            ("OTHER", unrelated),
        ]
        random.SystemRandom().shuffle(records)
        lines = [
            f"2026-09-12 12:{index:02d}:00 WARN [{tag}] {ip} - Payload: generated-{token}-{index}"
            for index, (tag, ip) in enumerate(records)
        ]
        WAF_PATH.write_text("\n".join(lines) + "\n")

        tags_by_ip = defaultdict(set)
        for tag, ip in records:
            tags_by_ip[ip].add(tag)
        expected_ips = sorted(
            ip for ip, tags in tags_by_ip.items() if {"SQLI", "XSS"}.issubset(tags)
        )

        verify_result = subprocess.run(
            ["openssl", "verify", "-CAfile", str(CA_PATH), str(CERT_PATH)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        expected_valid = verify_result.returncode == 0

        expected_subject = subprocess.check_output(
            ["openssl", "x509", "-noout", "-subject", "-in", str(CERT_PATH)],
            text=True,
            timeout=15,
        ).strip()
        if expected_subject.startswith("subject="):
            expected_subject = expected_subject[len("subject="):].strip()

        REPORT_PATH.unlink(missing_ok=True)
        result = subprocess.run(
            [str(SCRIPT_PATH)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Script failed on changed inputs with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert REPORT_PATH.is_file(), "Script did not recreate the report on changed inputs."

        try:
            report = json.loads(REPORT_PATH.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"Generated report is not valid JSON: {exc}")

        assert "certificate_valid" in report, "Key 'certificate_valid' missing from JSON."
        assert report["certificate_valid"] is expected_valid, (
            f"Expected certificate_valid={expected_valid}, got {report['certificate_valid']!r}"
        )
        assert "server_cert_subject" in report, "Key 'server_cert_subject' missing from JSON."
        assert report["server_cert_subject"] == expected_subject, (
            f"Expected subject {expected_subject!r}, got {report['server_cert_subject']!r}"
        )
        assert "threat_ips" in report, "Key 'threat_ips' missing from JSON."
        assert isinstance(report["threat_ips"], list), "threat_ips should be a list."
        assert report["threat_ips"] == expected_ips, (
            f"Expected sorted correlated IPs {expected_ips}, got {report['threat_ips']}"
        )
    finally:
        CERT_PATH.write_bytes(original_cert)
        WAF_PATH.write_bytes(original_log)
        REPORT_PATH.write_bytes(original_report)
        os.chmod(CERT_PATH, cert_mode)
        os.chmod(WAF_PATH, log_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
