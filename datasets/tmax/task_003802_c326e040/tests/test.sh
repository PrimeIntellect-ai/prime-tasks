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
import secrets
import string

import pytest
import requests

URL = "http://127.0.0.1:9999/login"
MALICIOUS = "admin' UNION SELECT null, 'root', null--"
EXPECTED = {"status": "escalated", "role": "root"}


def post_username(username):
    try:
        return requests.post(URL, json={"username": username}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to honeypot at {URL}: {e}")


def test_honeypot_malicious_payload():
    """Verify the honeypot correctly handles the extracted malicious SQLi payload."""
    response = post_username(MALICIOUS)
    assert response.status_code == 200, f"Expected HTTP 200 for malicious payload, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response was not valid JSON")

    assert data == EXPECTED, f"Expected JSON {EXPECTED}, got {data}"


def test_honeypot_normal_payload():
    """Verify the honeypot rejects normal/unmatched payloads."""
    response = post_username("admin")
    assert response.status_code == 403, f"Expected HTTP 403 for normal payload, got {response.status_code}"


def test_honeypot_rejects_other_usernames():
    """Exercise exact matching with variants and unpredictable nonmatching values."""
    usernames = [
        "",
        "root",
        MALICIOUS + " ",
        " " + MALICIOUS,
        MALICIOUS.upper(),
        MALICIOUS[:-1],
    ]
    alphabet = string.ascii_letters + string.digits + " '_-;"
    for _ in range(20):
        value = "probe-" + "".join(secrets.choice(alphabet) for _ in range(32))
        if value != MALICIOUS:
            usernames.append(value)

    for username in usernames:
        response = post_username(username)
        assert response.status_code == 403, (
            f"Expected HTTP 403 for unmatched username {username!r}, "
            f"got {response.status_code}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
