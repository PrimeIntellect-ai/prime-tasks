#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import requests
import pytest

def get_daemon_hash():
    daemon_path = "/home/user/suspicious_daemon"
    assert os.path.isfile(daemon_path), "Suspicious daemon not found."
    with open(daemon_path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def test_extracted_iocs():
    iocs_path = "/home/user/extracted_iocs.json"
    assert os.path.isfile(iocs_path), f"{iocs_path} does not exist."

    with open(iocs_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{iocs_path} is not valid JSON.")

    expected_hash = get_daemon_hash()
    expected_csp = "default-src 'none'; script-src http://evil.com;"

    assert data.get("binary_sha256") == expected_hash, "binary_sha256 in extracted_iocs.json is incorrect."
    assert data.get("injected_csp") == expected_csp, "injected_csp in extracted_iocs.json is incorrect."

def test_c2_port():
    port_path = "/home/user/c2_port.txt"
    assert os.path.isfile(port_path), f"{port_path} does not exist."

    with open(port_path, "r") as f:
        port = f.read().strip()

    assert port == "31337", f"Expected C2 port to be 31337, got {port}."

def test_service_status_endpoint():
    url = "http://127.0.0.1:8443/status"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /status is not valid JSON.")

    assert data.get("status") == "secure", "Expected JSON response {'status': 'secure'}."

    expected_csp = "default-src 'none'; script-src http://evil.com;"[::-1]
    csp_header = response.headers.get("Content-Security-Policy")
    assert csp_header == expected_csp, f"Expected CSP header to be {expected_csp}, got {csp_header}"

def test_service_report_endpoint():
    url = "http://127.0.0.1:8443/report"
    daemon_hash = get_daemon_hash()

    # Test with matching hash
    try:
        response_forbidden = requests.post(url, json={"ioc_hash": daemon_hash}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")

    assert response_forbidden.status_code == 403, f"Expected 403 Forbidden for matching hash, got {response_forbidden.status_code}"

    # Test with non-matching hash
    try:
        response_ok = requests.post(url, json={"ioc_hash": "dummy_hash"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")

    assert response_ok.status_code == 200, f"Expected 200 OK for non-matching hash, got {response_ok.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
