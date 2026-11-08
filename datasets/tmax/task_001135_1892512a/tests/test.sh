#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import ipaddress
import secrets
import urllib.parse
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
ENDPOINT = f"{BASE_URL}/api/v1/upload"
EXPECTED_CSP = "default-src 'self'; script-src 'none';"


def derive_password():
    lines = [line.strip() for line in Path("/app/system_auth.log").read_text().splitlines() if line.strip()]
    assert lines, "system_auth.log is empty"
    final_token = lines[-1].split()[-1].lower()
    assert len(final_token) == 64 and all(c in "0123456789abcdef" for c in final_token), "No valid SHA256 hash on the last log line"

    # The intercepted call specifies 'admin' followed by exactly three digits.
    matches = []
    for number in range(1000):
        candidate = f"admin{number:03d}"
        if hashlib.sha256(candidate.encode()).hexdigest() == final_token:
            matches.append(candidate)
    assert len(matches) == 1, "The evidence did not yield exactly one password"
    return matches[0]


def derive_attacker_ip():
    matches = []
    for line in Path("/app/nginx_access.log").read_text().splitlines():
        parts = line.split('"')
        if len(parts) < 3:
            continue
        prefix, request, suffix = parts[0], parts[1], parts[2]
        request_parts = request.split()
        response_parts = suffix.split()
        if len(request_parts) < 2 or not response_parts or response_parts[0] != "200":
            continue

        target = request_parts[1]
        for _ in range(3):
            target = urllib.parse.unquote(target)
        target = target.replace("\\", "/")
        if "../" not in target or "/etc/shadow" not in target:
            continue

        ip = prefix.split()[0]
        ipaddress.IPv4Address(ip)
        matches.append(ip)

    assert len(matches) == 1, "Expected exactly one successful traversal download of /etc/shadow"
    return matches[0]


PASSWORD = derive_password()
ATTACKER_IP = derive_attacker_ip()
EXPECTED_AUTH_HEADER = f"{PASSWORD}:{ATTACKER_IP}"


def check_csp_header(response):
    csp = response.headers.get("Content-Security-Policy")
    assert csp is not None, "Content-Security-Policy header is missing from the response."
    assert csp == EXPECTED_CSP, f"Content-Security-Policy header is incorrect. Expected: {EXPECTED_CSP}, Got: {csp}"


def post(payload, auth=None):
    headers = {} if auth is None else {"X-Incident-Auth": auth}
    try:
        response = requests.post(ENDPOINT, headers=headers, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {ENDPOINT}: {exc}")
    check_csp_header(response)
    return response


def test_missing_auth():
    response = post({"filename": "safe.txt"})
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}. Response: {response.text}"


def test_incorrect_auth():
    response = post({"filename": "safe.txt"}, f"wrongpassword:{ATTACKER_IP}")
    assert response.status_code == 401, f"Expected 401 for incorrect auth, got {response.status_code}. Response: {response.text}"


def test_path_traversal_forward_slash():
    response = post({"filename": "../../../etc/passwd"}, EXPECTED_AUTH_HEADER)
    assert response.status_code == 400, f"Expected 400 for path traversal '../', got {response.status_code}. Response: {response.text}"


def test_path_traversal_backslash():
    response = post({"filename": "..\\..\\..\\windows\\system32"}, EXPECTED_AUTH_HEADER)
    assert response.status_code == 400, f"Expected 400 for path traversal '..\\', got {response.status_code}. Response: {response.text}"


def test_successful_upload():
    response = post({"filename": "report.pdf"}, EXPECTED_AUTH_HEADER)
    assert response.status_code == 200, f"Expected 200 for safe filename, got {response.status_code}. Response: {response.text}"


def test_randomized_safe_filenames():
    for _ in range(16):
        filename = f"upload-{secrets.token_hex(12)}.{secrets.choice(['txt', 'pdf', 'dat'])}"
        response = post({"filename": filename}, EXPECTED_AUTH_HEADER)
        assert response.status_code == 200, f"Expected 200 for randomized safe filename {filename!r}, got {response.status_code}"


def test_randomized_forward_traversals():
    for _ in range(12):
        filename = f"folder-{secrets.token_hex(5)}/../file-{secrets.token_hex(7)}.txt"
        response = post({"filename": filename}, EXPECTED_AUTH_HEADER)
        assert response.status_code == 400, f"Expected 400 for randomized '../' filename {filename!r}, got {response.status_code}"


def test_randomized_backslash_traversals():
    for _ in range(12):
        filename = f"folder-{secrets.token_hex(5)}..\\file-{secrets.token_hex(7)}.txt"
        response = post({"filename": filename}, EXPECTED_AUTH_HEADER)
        assert response.status_code == 400, f"Expected 400 for randomized '..\\' filename {filename!r}, got {response.status_code}"


def test_randomized_incorrect_authentication():
    for _ in range(12):
        wrong_auth = f"{secrets.token_hex(10)}:{ATTACKER_IP}"
        assert wrong_auth != EXPECTED_AUTH_HEADER
        response = post({"filename": f"safe-{secrets.token_hex(8)}.txt"}, wrong_auth)
        assert response.status_code == 401, f"Expected 401 for randomized incorrect authentication, got {response.status_code}"


def test_csp_on_other_responses():
    for _ in range(3):
        path = f"/{secrets.token_hex(12)}"
        try:
            response = requests.get(BASE_URL + path, timeout=5)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to the service at {BASE_URL + path}: {exc}")
        check_csp_header(response)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
