#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess
import re
from datetime import datetime
import pytest

def get_cert_info(cert_path):
    out = subprocess.check_output(
        ['openssl', 'x509', '-in', cert_path, '-noout', '-issuer', '-enddate', '-nameopt', 'RFC2253'], 
        text=True
    )
    issuer_line = next(line for line in out.splitlines() if line.startswith('issuer='))
    enddate_line = next(line for line in out.splitlines() if line.startswith('notAfter='))

    issuer_str = issuer_line.split('=', 1)[1]
    parts = issuer_str.split(',')
    cn = None
    o = None
    for part in parts:
        if part.startswith('CN='):
            cn = part[3:]
        elif part.startswith('O='):
            o = part[2:]

    issuer = cn if cn else o

    date_str = enddate_line.split('=', 1)[1].strip()
    dt = datetime.strptime(date_str, '%b %d %H:%M:%S %Y %Z')
    expiry = dt.strftime('%Y-%m-%d')
    return issuer, expiry

def test_audit_trail_exists():
    assert os.path.isfile("/home/user/audit_trail.json"), "The file /home/user/audit_trail.json does not exist."

def test_audit_trail_content():
    with open("/home/user/audit_trail.json") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/audit_trail.json is not a valid JSON file.")

    assert "audit_results" in data, "Missing 'audit_results' key in JSON."
    results = data["audit_results"]
    assert isinstance(results, list), "'audit_results' must be a list."

    # Check sorting
    services = [r.get("service", "") for r in results]
    assert services == sorted(services), "'audit_results' must be sorted alphabetically by service."

    assert len(results) == 2, f"Expected 2 services in audit_results, found {len(results)}."

    alpha = next((r for r in results if r.get("service") == "service_alpha"), None)
    beta = next((r for r in results if r.get("service") == "service_beta"), None)

    assert alpha is not None, "Missing 'service_alpha' in results."
    assert beta is not None, "Missing 'service_beta' in results."

    alpha_issuer, alpha_expiry = get_cert_info("/home/user/audit_data/certs/service_alpha.pem")
    beta_issuer, beta_expiry = get_cert_info("/home/user/audit_data/certs/service_beta.pem")

    # Service Alpha assertions
    assert alpha.get("cert_issuer") == alpha_issuer, f"service_alpha cert_issuer mismatch. Expected {alpha_issuer}"
    assert alpha.get("cert_expiry") == alpha_expiry, f"service_alpha cert_expiry mismatch. Expected {alpha_expiry}"
    assert alpha.get("missing_headers") == [], "service_alpha should have no missing_headers"
    assert alpha.get("non_compliant_cookies") == [], "service_alpha should have no non_compliant_cookies"

    # Service Beta assertions
    assert beta.get("cert_issuer") == beta_issuer, f"service_beta cert_issuer mismatch. Expected {beta_issuer}"
    assert beta.get("cert_expiry") == beta_expiry, f"service_beta cert_expiry mismatch. Expected {beta_expiry}"

    expected_missing_headers = ["Content-Security-Policy", "X-Frame-Options"]
    actual_missing_headers = beta.get("missing_headers", [])
    assert sorted(actual_missing_headers) == sorted(expected_missing_headers), \
        f"service_beta missing_headers mismatch. Expected {expected_missing_headers}"

    expected_non_compliant_cookies = ["auth_token"]
    actual_non_compliant_cookies = beta.get("non_compliant_cookies", [])
    assert sorted(actual_non_compliant_cookies) == sorted(expected_non_compliant_cookies), \
        f"service_beta non_compliant_cookies mismatch. Expected {expected_non_compliant_cookies}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
