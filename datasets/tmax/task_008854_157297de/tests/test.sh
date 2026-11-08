#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import subprocess
import pytest


def get_expired_cert():
    certs_dir = "/home/user/certs"
    if not os.path.isdir(certs_dir):
        return None
    for f in os.listdir(certs_dir):
        if f.endswith(".pem"):
            path = os.path.join(certs_dir, f)
            # openssl x509 -checkend 0 returns 0 if valid, 1 if expired
            res = subprocess.run(
                ["openssl", "x509", "-checkend", "0", "-noout", "-in", path],
                capture_output=True
            )
            if res.returncode != 0:
                return f
    return None


def get_expected_ips(service_name):
    expected_ips = set()
    log_path = "/home/user/access.log"
    if not os.path.isfile(log_path):
        return []
    with open(log_path, "r") as f:
        for line in f:
            parts = line.split()
            # 2023-10-01T10:05:00Z payment 10.0.0.5 STATUS: SUCCESS
            if len(parts) >= 5 and parts[1] == service_name and "STATUS: SUCCESS" in line:
                expected_ips.add(parts[2])
    return sorted(list(expected_ips))


def test_expired_cert_file():
    expired_cert = get_expired_cert()
    assert expired_cert is not None, "Could not determine the expired certificate."

    cert_txt_path = "/home/user/expired_cert.txt"
    assert os.path.isfile(cert_txt_path), f"File missing: {cert_txt_path}"

    with open(cert_txt_path, "r") as f:
        content = f.read().strip()

    assert content == expired_cert, f"Expected '{expired_cert}' in {cert_txt_path}, but got '{content}'"


def test_suspect_ips_file():
    expired_cert = get_expired_cert()
    assert expired_cert is not None, "Could not determine the expired certificate."
    service_name = expired_cert.replace(".pem", "")

    expected_ips = get_expected_ips(service_name)

    ips_txt_path = "/home/user/suspect_ips.txt"
    assert os.path.isfile(ips_txt_path), f"File missing: {ips_txt_path}"

    with open(ips_txt_path, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert sorted(actual_ips) == expected_ips, f"Expected IPs {expected_ips} in {ips_txt_path}, but got {sorted(actual_ips)}"


def test_audit_report_json():
    expired_cert = get_expired_cert()
    assert expired_cert is not None, "Could not determine the expired certificate."
    service_name = expired_cert.replace(".pem", "")
    expected_ips = get_expected_ips(service_name)

    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"File missing: {report_path}"

    try:
        with open(report_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {report_path} is not valid JSON.")

    assert data.get("service") == service_name, f"Expected service '{service_name}' in JSON, got {data.get('service')}"
    assert data.get("status") == "compromised", f"Expected status 'compromised' in JSON, got {data.get('status')}"
    assert data.get("exfiltration_prevented") is True, "Expected 'exfiltration_prevented' to be True in JSON (script wasn't run in isolated sandbox properly?)"
    assert sorted(data.get("unique_ips", [])) == expected_ips, f"Expected unique_ips {expected_ips} in JSON, got {sorted(data.get('unique_ips', []))}"


def test_required_bwrap_execution_reproduces_report():
    script_path = "/home/user/generate_report.py"
    report_path = "/home/user/audit_report.json"

    assert os.path.exists(script_path), f"File missing: {script_path}"
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"Expected a regular file: {script_path}"
    assert os.path.exists(report_path), f"File missing: {report_path}"
    assert stat.S_ISREG(os.lstat(report_path).st_mode), f"Expected a regular file: {report_path}"

    with open(report_path, "rb") as f:
        submitted_report = f.read()

    os.unlink(report_path)
    command = [
        "/usr/bin/bwrap",
        "--unshare-net",
        "--ro-bind", "/", "/",
        "--bind", "/home/user", "/home/user",
        "python3", "/home/user/generate_report.py",
        "/home/user/suspect_ips.txt", "/home/user/audit_report.json",
    ]
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        env={"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
    )
    assert result.returncode == 0, (
        "generate_report.py failed under the required bwrap sandbox. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(report_path), "Sandboxed script did not create audit_report.json"
    assert stat.S_ISREG(os.lstat(report_path).st_mode), f"Expected a regular file: {report_path}"

    with open(report_path, "rb") as f:
        sandboxed_report = f.read()
    assert submitted_report == sandboxed_report, (
        "The submitted audit report does not match a report freshly generated "
        "by the required network-isolated bwrap command."
    )

    try:
        data = json.loads(sandboxed_report)
    except json.JSONDecodeError:
        pytest.fail(f"File {report_path} generated in the sandbox is not valid JSON.")

    expired_cert = get_expired_cert()
    assert expired_cert is not None, "Could not determine the expired certificate."
    service_name = expired_cert.replace(".pem", "")
    expected_ips = get_expected_ips(service_name)
    assert data.get("service") == service_name
    assert data.get("status") == "compromised"
    assert data.get("exfiltration_prevented") is True
    assert sorted(data.get("unique_ips", [])) == expected_ips
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
