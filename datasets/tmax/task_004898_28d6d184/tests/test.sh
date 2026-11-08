#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
REPORT_PATH = "/home/user/report.txt"
DATA_PATH = "/home/user/server_data"


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    try:
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {SCRIPT_PATH} timed out during execution.")
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not created by the script."
    with open(REPORT_PATH, "r") as report:
        return report.read().strip()


def assert_report(content, expected_lines):
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in report, got {len(actual_lines)}.\nContent:\n{content}"
    )
    for expected, actual in zip(expected_lines, actual_lines):
        assert actual == expected, f"Mismatch in report. Expected: '{expected}', Got: '{actual}'"


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_analyze_script_execution_and_output():
    content = run_script()
    expected_lines = [
        "COMPROMISED_FILE: app.js",
        "ROGUE_ISSUER: EvilRogueCA-999",
        "ATTACKER_IP: 203.0.113.8",
    ]
    assert_report(content, expected_lines)


def test_script_analyzes_changed_inputs():
    token = secrets.token_hex(6)
    compromised = f"asset-{token}.js"
    safe_html = f"page-{token}.html"
    safe_css = f"theme-{token}.css"
    issuer_cn = f"AuditIssuer-{token}"
    leaf_cn = f"server-{token}.internal"
    attacker_ip = f"198.51.100.{10 + secrets.randbelow(190)}"

    backup_root = tempfile.mkdtemp(prefix="server-data-backup-")
    backup_data = os.path.join(backup_root, "server_data")
    shutil.copytree(DATA_PATH, backup_data)

    try:
        shutil.rmtree(DATA_PATH)
        www = os.path.join(DATA_PATH, "www")
        os.makedirs(www)

        originals = {
            safe_html: b"<html><body>Dynamic fixture</body></html>\n",
            compromised: b"function launch() { return 'clean'; }\n",
            safe_css: b"body { background: white; }\n",
        }
        for name, data in originals.items():
            with open(os.path.join(www, name), "wb") as output:
                output.write(data)

        with open(os.path.join(DATA_PATH, "hashes.txt"), "w") as hashes:
            for name in sorted(originals):
                digest = hashlib.sha256(originals[name]).hexdigest()
                hashes.write(f"{digest}  {name}\n")

        with open(os.path.join(www, compromised), "wb") as output:
            output.write(b"function launch() { eval(atob('ZXZpbA==')); }\n")

        cert_work = tempfile.mkdtemp(prefix="cert-work-")
        try:
            ca_key = os.path.join(cert_work, "ca.key")
            ca_cert = os.path.join(cert_work, "ca.pem")
            leaf_key = os.path.join(cert_work, "leaf.key")
            leaf_csr = os.path.join(cert_work, "leaf.csr")
            serial = os.path.join(cert_work, "ca.srl")
            cert_path = os.path.join(DATA_PATH, "cert.pem")

            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", ca_key, "-out", ca_cert, "-days", "2",
                "-subj", f"/C=US/O=Dynamic Audit CA/CN={issuer_cn}",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([
                "openssl", "req", "-newkey", "rsa:2048", "-nodes",
                "-keyout", leaf_key, "-out", leaf_csr,
                "-subj", f"/C=US/O=Dynamic Web/CN={leaf_cn}",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([
                "openssl", "x509", "-req", "-in", leaf_csr,
                "-CA", ca_cert, "-CAkey", ca_key, "-CAcreateserial",
                "-CAserial", serial, "-out", cert_path, "-days", "2",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        finally:
            shutil.rmtree(cert_work)

        log_lines = [
            f'192.0.2.21 - - [11/Sep/2026:10:00:00 +0000] "GET /{safe_html}?x=base64_decode(ZGVjb3k=) HTTP/1.1" 200 100 "-" "AuditClient/1.0"',
            f'192.0.2.22 - - [11/Sep/2026:10:01:00 +0000] "GET /{compromised} HTTP/1.1" 200 200 "-" "AuditClient/1.0"',
            f'{attacker_ip} - - [11/Sep/2026:10:02:00 +0000] "GET /{compromised}?cmd=base64_decode(cGF5bG9hZA==) HTTP/1.1" 200 300 "-" "AuditClient/1.0"',
            f'192.0.2.23 - - [11/Sep/2026:10:03:00 +0000] "GET /{safe_css} HTTP/1.1" 200 400 "-" "AuditClient/1.0"',
        ]
        with open(os.path.join(DATA_PATH, "access.log"), "w") as access_log:
            access_log.write("\n".join(log_lines) + "\n")

        content = run_script()
        assert_report(content, [
            f"COMPROMISED_FILE: {compromised}",
            f"ROGUE_ISSUER: {issuer_cn}",
            f"ATTACKER_IP: {attacker_ip}",
        ])
    finally:
        if os.path.exists(DATA_PATH):
            shutil.rmtree(DATA_PATH)
        shutil.copytree(backup_data, DATA_PATH)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
