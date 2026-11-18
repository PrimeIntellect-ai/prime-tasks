#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

HOME = Path('/home/user')
SCRIPT = HOME / 'generate_audit.py'
REPORT = HOME / 'audit_report.json'
BINARY = HOME / 'suspicious_module.so'
LOG = HOME / 'web_traffic.log'


def run_script():
    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()

    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'generate_audit.py exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )
    assert REPORT.exists(), 'generate_audit.py did not create audit_report.json.'
    assert REPORT.is_file(), 'generate_audit.py did not create a regular report file.'

    try:
        with REPORT.open('r') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'generate_audit.py produced invalid JSON: {exc}')


def derive_expected(binary_bytes, log_text):
    ua_matches = re.findall(rb'User-Agent:\s*(X-Compliance-Bot/[^\r\n]+)', binary_bytes)
    cookie_matches = re.findall(rb'Cookie:\s*(auth_token_v2=[^\r\n]+)', binary_bytes)
    assert len(ua_matches) == 1, 'Verifier fixture must contain exactly one matching User-Agent.'
    assert len(cookie_matches) == 1, 'Verifier fixture must contain exactly one matching Cookie.'

    user_agent = ua_matches[0].decode('utf-8').strip()
    cookie = cookie_matches[0].decode('utf-8').strip()
    malicious_ips = set()

    for line in log_text.splitlines():
        fields = [field.strip() for field in line.split('|')]
        if len(fields) == 6 and fields[4] == user_agent and fields[5] == cookie:
            malicious_ips.add(fields[0])

    return {
        'extracted_iocs': {
            'user_agent': user_agent,
            'cookie': cookie,
        },
        'malicious_ips': sorted(malicious_ips),
    }


def test_generate_audit_script_exists_executes_and_uses_inputs():
    assert SCRIPT.exists(), f'The expected script {SCRIPT} does not exist.'
    assert SCRIPT.is_file(), f'The path {SCRIPT} is not a file.'
    assert not SCRIPT.is_symlink(), f'The path {SCRIPT} must be a Python script, not a symlink.'

    # Execute against the supplied incident files after deleting any prewritten report.
    run_script()

    original_binary = BINARY.read_bytes()
    original_log = LOG.read_bytes()

    original_ua = re.findall(rb'User-Agent:\s*(X-Compliance-Bot/[^\r\n]+)', original_binary)
    original_cookie = re.findall(rb'Cookie:\s*(auth_token_v2=[^\r\n]+)', original_binary)
    assert len(original_ua) == 1 and len(original_cookie) == 1

    nonce = uuid.uuid4().hex
    dynamic_ua = f'X-Compliance-Bot/audit-{nonce}'.encode()
    dynamic_cookie = f'auth_token_v2={nonce}_dynamic'.encode()
    decoy_ua = f'X-Compliance-Bot/decoy-{nonce}'
    decoy_cookie = f'auth_token_v2=decoy_{nonce}'

    dynamic_binary = original_binary.replace(original_ua[0], dynamic_ua).replace(
        original_cookie[0], dynamic_cookie
    )
    dynamic_log = '\n'.join([
        f'203.0.113.9 | 2026-01-01T00:00:00Z | GET /decoy | 200 | {decoy_ua} | {decoy_cookie}',
        f'198.51.100.42 | 2026-01-01T00:01:00Z | POST /beacon | 200 | {dynamic_ua.decode()} | {dynamic_cookie.decode()}',
        f'192.0.2.77 | 2026-01-01T00:02:00Z | GET /ua-only | 200 | {dynamic_ua.decode()} | {decoy_cookie}',
        f'192.0.2.88 | 2026-01-01T00:03:00Z | GET /cookie-only | 200 | {decoy_ua} | {dynamic_cookie.decode()}',
        f'192.0.2.5 | 2026-01-01T00:04:00Z | GET /beacon | 200 | {dynamic_ua.decode()} | {dynamic_cookie.decode()}',
        f'198.51.100.42 | 2026-01-01T00:05:00Z | GET /duplicate | 200 | {dynamic_ua.decode()} | {dynamic_cookie.decode()}',
        '',
    ])
    expected = derive_expected(dynamic_binary, dynamic_log)

    try:
        BINARY.write_bytes(dynamic_binary)
        LOG.write_text(dynamic_log)
        dynamic_report = run_script()
        assert dynamic_report == expected, (
            'The generated report was not derived correctly from the modified binary and log. '
            f'Expected {expected!r}, got {dynamic_report!r}.'
        )
    finally:
        BINARY.write_bytes(original_binary)
        LOG.write_bytes(original_log)
        if REPORT.exists() or REPORT.is_symlink():
            REPORT.unlink()
        subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd=str(HOME),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )


def test_audit_report_exists():
    """Test that the audit report JSON file was generated."""
    report_path = '/home/user/audit_report.json'
    assert os.path.exists(report_path), f'The expected output file {report_path} does not exist.'
    assert os.path.isfile(report_path), f'The path {report_path} is not a file.'


def test_audit_report_content():
    """Test that the audit report contains the correct IOCs and malicious IPs."""
    report_path = '/home/user/audit_report.json'

    try:
        with open(report_path, 'r') as f:
            report_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'The file {report_path} does not contain valid JSON.')

    # Check top-level keys
    assert 'extracted_iocs' in report_data, "The JSON is missing the 'extracted_iocs' key."
    assert 'malicious_ips' in report_data, "The JSON is missing the 'malicious_ips' key."

    # Verify extracted IOCs
    iocs = report_data['extracted_iocs']
    assert 'user_agent' in iocs, "The 'extracted_iocs' object is missing the 'user_agent' key."
    assert 'cookie' in iocs, "The 'extracted_iocs' object is missing the 'cookie' key."

    expected_user_agent = 'X-Compliance-Bot/v2.4.1-alpha'
    expected_cookie = 'auth_token_v2=xyz_9988776655_abc'

    assert iocs['user_agent'] == expected_user_agent, f"Expected user_agent '{expected_user_agent}', but got '{iocs['user_agent']}'."
    assert iocs['cookie'] == expected_cookie, f"Expected cookie '{expected_cookie}', but got '{iocs['cookie']}'."

    # Verify malicious IPs
    malicious_ips = report_data['malicious_ips']
    assert isinstance(malicious_ips, list), "The 'malicious_ips' value must be a list."

    expected_ips = ['10.0.5.55', '172.16.0.4']

    # Check if IPs are correct and sorted
    assert malicious_ips == expected_ips, f'Expected malicious_ips to be {expected_ips}, but got {malicious_ips}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
