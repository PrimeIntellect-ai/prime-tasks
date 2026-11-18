#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import py_compile
import secrets
import subprocess

import pytest

SCRIPT = "/home/user/analyze_incident.py"
REPORT = "/home/user/enforcement_report.json"


def run_script():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_incident.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_original_analysis():
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} is missing."
    run_script()


def test_analyze_incident_script_exists():
    path = "/home/user/analyze_incident.py"
    assert os.path.isfile(path), f"Expected script {path} is missing."


def test_enforcement_report_exists():
    path = "/home/user/enforcement_report.json"
    assert os.path.isfile(path), f"Expected report file {path} is missing."


def test_enforcement_report_content():
    path = "/home/user/enforcement_report.json"
    assert os.path.isfile(path), f"Expected report file {path} is missing."

    with open(path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected_ip = "172.16.0.42"
    expected_hash = "e382bbcdcf6071485dbce46fb2621189"
    expected_password = "devsecops2023"
    expected_cn = "EvilHacker"

    assert report.get("attacker_ip") == expected_ip, f"Expected attacker_ip to be '{expected_ip}', but got '{report.get('attacker_ip')}'."
    assert report.get("hardcoded_hash") == expected_hash, f"Expected hardcoded_hash to be '{expected_hash}', but got '{report.get('hardcoded_hash')}'."
    assert report.get("cracked_password") == expected_password, f"Expected cracked_password to be '{expected_password}', but got '{report.get('cracked_password')}'."
    assert report.get("cert_issuer_cn") == expected_cn, f"Expected cert_issuer_cn to be '{expected_cn}', but got '{report.get('cert_issuer_cn')}'."


def test_z_analysis_uses_supplied_artifacts_programmatically():
    token = secrets.token_hex(8)
    expected_ip = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}"
    expected_password = f"incident-{token}"
    expected_hash = hashlib.md5(expected_password.encode()).hexdigest()
    expected_cn = f"AuditIssuer-{token}"

    with open("/home/user/web_logs.txt", "w") as f:
        f.write(
            '203.0.113.9 - - [11/Sep/2026:10:00:00 +0000] "POST /api/v1/deploy HTTP/1.1" 403 17\n'
            '198.51.100.8 - - [11/Sep/2026:10:00:01 +0000] "GET /api/v1/status HTTP/1.1" 200 4\n'
            f'{expected_ip} - - [11/Sep/2026:10:00:02 +0000] "POST /api/v1/deploy HTTP/1.1" 201 321\n'
        )

    source_path = f"/tmp/rogue_auth_{token}.py"
    with open(source_path, "w") as f:
        f.write(
            "def authenticate(password):\n"
            f"    SECRET_HASH = {expected_hash!r}\n"
            "    import hashlib\n"
            "    return hashlib.md5(password.encode()).hexdigest() == SECRET_HASH\n"
        )
    py_compile.compile(source_path, cfile="/home/user/rogue_auth.pyc", doraise=True)
    os.remove(source_path)

    with open("/home/user/passwords.txt", "w") as f:
        f.write("not-the-password\n")
        f.write(f"{expected_password}\n")
        f.write("another-decoy\n")

    cert_result = subprocess.run(
        [
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", f"/tmp/audit_key_{token}.pem",
            "-out", "/home/user/rogue_cert.pem",
            "-days", "1", "-nodes", "-subj", f"/CN={expected_cn}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert cert_result.returncode == 0, cert_result.stderr

    run_script()
    assert os.path.isfile(REPORT), f"Expected report file {REPORT} is missing after execution."
    with open(REPORT, "r") as f:
        report = json.load(f)

    expected = {
        "attacker_ip": expected_ip,
        "hardcoded_hash": expected_hash,
        "cracked_password": expected_password,
        "cert_issuer_cn": expected_cn,
    }
    assert report == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
