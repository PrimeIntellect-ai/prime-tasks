#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess


def get_expected_machine():
    try:
        output = subprocess.check_output(
            ["readelf", "-h", "/home/user/audit_target/app_bin"],
            text=True
        )
        for line in output.splitlines():
            if "Machine:" in line:
                return line.split("Machine:", 1)[1].strip()
    except Exception:
        return None
    return None


def get_expected_cert_status():
    result = subprocess.run(
        [
            "openssl", "verify",
            "-CAfile", "/home/user/audit_target/root.pem",
            "-untrusted", "/home/user/audit_target/intermediate.pem",
            "/home/user/audit_target/leaf.pem"
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    return "VALID" if result.returncode == 0 else "INVALID"


def test_audit_report_exists_and_correct():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"The audit report file {report_path} was not created."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_machine = get_expected_machine()
    assert expected_machine is not None, "Could not determine expected machine type from app_bin."
    expected_cert_status = get_expected_cert_status()

    expected_lines = [
        "[AUDIT TRAIL]",
        f"Binary_Machine: {expected_machine}",
        f"Cert_Status: {expected_cert_status}",
        "CSP_Status: ENFORCED"
    ]

    content_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(content_lines) == 4, f"Expected 4 lines in the report, but got {len(content_lines)}."
    assert content_lines[0] == expected_lines[0], f"Expected first line to be '{expected_lines[0]}', got '{content_lines[0]}'."
    assert content_lines[1] == expected_lines[1], f"Expected Binary_Machine line to be '{expected_lines[1]}', got '{content_lines[1]}'."
    assert content_lines[2] == expected_lines[2], f"Expected Cert_Status line to be '{expected_lines[2]}', got '{content_lines[2]}'."
    assert content_lines[3] == expected_lines[3], f"Expected CSP_Status line to be '{expected_lines[3]}', got '{content_lines[3]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
