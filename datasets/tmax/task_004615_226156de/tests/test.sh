#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import subprocess
import pytest

def test_malicious_ips_f1_score():
    pred_file = "/home/user/malicious_ips.json"
    truth_file = "/tests/true_ips.json"

    assert os.path.exists(pred_file), f"Prediction file missing at {pred_file}"

    with open(pred_file) as f:
        try:
            pred_data = json.load(f)
            pred = set(pred_data)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {pred_file} as valid JSON.")

    with open(truth_file) as f:
        truth = set(json.load(f))

    if not pred and not truth:
        f1 = 1.0
    elif not pred or not truth:
        f1 = 0.0
    else:
        tp = len(pred & truth)
        fp = len(pred - truth)
        fn = len(truth - pred)
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1 = 2 * (precision * recall) / (precision + recall) if precision + recall > 0 else 0.0

    assert f1 >= 0.95, f"F1 score {f1:.4f} is below threshold 0.95. Detected {len(pred)} IPs, Truth is {len(truth)} IPs."

def test_suid_audit():
    audit_file = "/home/user/suid_audit.txt"
    truth_file = "/tests/true_suid.txt"

    assert os.path.exists(audit_file), f"Audit file missing at {audit_file}"

    with open(audit_file) as f:
        audit_paths = set(line.strip() for line in f if line.strip())
    with open(truth_file) as f:
        truth_paths = set(line.strip() for line in f if line.strip())

    missing = truth_paths - audit_paths
    extra = audit_paths - truth_paths

    error_msg = "SUID paths mismatch."
    if missing:
        error_msg += f" Missing paths: {missing}."
    if extra:
        error_msg += f" Extra paths: {extra}."

    assert audit_paths == truth_paths, error_msg

def test_nginx_tls_and_csp():
    cmd = [
        "curl", "-sS", "--cacert", "/app/ca/ca.crt", "-D", "-",
        "https://localhost:8443/api/status"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 0, f"Curl failed to verify the certificate chain or connect. Exit code {result.returncode}, stderr: {result.stderr}"

    headers_raw = result.stdout.split('\r\n')

    expected_csp_value = "default-src 'self'; script-src 'self' https://trusted.cdn.com; object-src 'none';"
    csp_found = False

    for line in headers_raw:
        if line.lower().startswith("content-security-policy:"):
            value = line.split(":", 1)[1].strip()
            if value == expected_csp_value:
                csp_found = True
                break

    assert csp_found, f"Expected CSP header not found or incorrect. Expected value: '{expected_csp_value}'. Response headers:\n{result.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
