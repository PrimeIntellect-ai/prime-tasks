#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import requests
import pytest

MASTER_KEY = "f4a2b9d1"
URL = "http://127.0.0.1:8080/scan"


def expected_token(challenge):
    return hex((int(MASTER_KEY, 16) ^ (challenge * 1337)) % 0xFFFFFFFF)[2:]


def request_scan(challenge, token):
    try:
        return requests.get(
            URL,
            headers={
                "X-Challenge": str(challenge),
                "X-Auth-Token": token,
            },
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to proxy service on {URL}: {e}")


def test_sshd_config_hardened():
    """Verify the SSH hardened configuration file exists and contains the exact required directives."""
    config_path = "/home/user/sshd_config_hardened"
    assert os.path.exists(config_path), f"SSH configuration file missing: {config_path}"
    assert os.path.isfile(config_path), f"Path is not a file: {config_path}"

    with open(config_path, 'r') as f:
        lines = f.readlines()

    active_directives = []
    for line in lines:
        line = line.strip()
        if line and not line.startswith('#'):
            normalized_line = re.sub(r'\s+', ' ', line)
            active_directives.append(normalized_line)

    expected_directives = {
        "PermitRootLogin no",
        "PasswordAuthentication no",
        "X11Forwarding no",
        "MaxAuthTries 3",
        "Protocol 2"
    }

    actual_directives = set(active_directives)
    missing = expected_directives - actual_directives
    extra = actual_directives - expected_directives

    assert not missing, f"Missing required SSH directives: {missing}"
    assert not extra, f"Found extra/unauthorized SSH directives: {extra}"


def test_proxy_service_valid_request():
    """Verify the proxy service correctly authorizes a valid request."""
    challenge = 100
    response = request_scan(challenge, expected_token(challenge))

    assert response.status_code == 200, f"Expected HTTP 200 OK for valid request, got {response.status_code}"
    assert response.text.strip() == "SCAN_AUTHORIZED", f"Expected body 'SCAN_AUTHORIZED', got '{response.text}'"


def test_proxy_service_invalid_request():
    """Verify the proxy service correctly denies an invalid request."""
    response = request_scan(100, "deadbeef")

    assert response.status_code == 403, f"Expected HTTP 403 Forbidden for invalid request, got {response.status_code}"
    assert response.text.strip() == "ACCESS_DENIED", f"Expected body 'ACCESS_DENIED', got '{response.text}'"


def test_proxy_service_dynamic_challenge():
    """Verify the proxy service computes tokens dynamically for fixed and unpredictable challenges."""
    challenges = [42]
    challenges.extend(secrets.randbelow(1_000_000) for _ in range(8))

    for challenge in challenges:
        token = expected_token(challenge)
        response = request_scan(challenge, token)
        assert response.status_code == 200, (
            f"Expected HTTP 200 OK for valid challenge {challenge}, got {response.status_code}"
        )
        assert response.text.strip() == "SCAN_AUTHORIZED", (
            f"Expected body 'SCAN_AUTHORIZED' for challenge {challenge}, got '{response.text}'"
        )

        invalid_response = request_scan(challenge, token + "0")
        assert invalid_response.status_code == 403, (
            f"Expected HTTP 403 Forbidden for invalid token at challenge {challenge}, "
            f"got {invalid_response.status_code}"
        )
        assert invalid_response.text.strip() == "ACCESS_DENIED", (
            f"Expected body 'ACCESS_DENIED' for invalid token at challenge {challenge}, "
            f"got '{invalid_response.text}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
