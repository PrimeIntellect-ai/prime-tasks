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
import json
import os
import random
import secrets
import stat
import subprocess

import requests
from requests.auth import HTTPBasicAuth

BASE_URL = "http://127.0.0.1:8000"
EXPECTED_CREDS = {
    "admin": "hunter2",
    "db_user": "secret",
    "backup_svc": "apple",
}


def test_recovered_creds_file():
    path = "/app/recovered_creds.json"
    assert os.path.isfile(path), f"File missing: {path}"

    st = os.stat(path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Incorrect permissions on {path}: expected 0600, got {oct(perms)}"

    with open(path, "r") as f:
        try:
            creds = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{path} is not valid JSON"

    assert creds == EXPECTED_CREDS, f"Contents of {path} do not match the expected recovered credentials."


def get_legacy_token(username, password):
    result = subprocess.run(
        ["/app/legacy_token_gen", username, password],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def assert_ok_body(resp):
    try:
        body = resp.json()
    except ValueError:
        assert False, f"Expected JSON response body, got: {resp.text!r}"
    assert body == {"status": "ok"}, f"Expected {{'status': 'ok'}}, got {body!r}"


def verify(username, password, expected_status):
    resp = requests.get(
        f"{BASE_URL}/verify",
        auth=HTTPBasicAuth(username, password),
        timeout=2,
    )
    assert resp.status_code == expected_status, (
        f"Expected {expected_status} for {username!r} with supplied password, "
        f"got {resp.status_code}. Response: {resp.text}"
    )
    if expected_status == 200:
        assert_ok_body(resp)
    return resp


def fresh_password(prefix):
    return f"{prefix}_{secrets.token_urlsafe(20)}"


def token_distinct_from(username, forbidden_tokens):
    while True:
        password = fresh_password("wrong")
        token = get_legacy_token(username, password)
        if token not in forbidden_tokens:
            return token


def randomized_rotation_round(username, current_password, all_users):
    new_password = fresh_password(f"new_{username}")
    valid_token = get_legacy_token(username, current_password)
    future_token = get_legacy_token(username, new_password)

    wrong_token = token_distinct_from(username, {valid_token, future_token})
    other_user = next(name for name in all_users if name != username)
    other_token = get_legacy_token(other_user, current_password)
    if other_token in {valid_token, future_token}:
        other_token = token_distinct_from(other_user, {valid_token, future_token})

    attempts = [
        (True, valid_token, new_password),
        (False, None, fresh_password("missing_header")),
        (False, wrong_token, fresh_password("wrong_password_token")),
        (False, other_token, fresh_password("wrong_user_token")),
    ]
    random.SystemRandom().shuffle(attempts)

    expected_current = current_password
    failed_candidates = []
    for is_valid, token, candidate_password in attempts:
        headers = {} if token is None else {"X-Legacy-Token": token}
        resp = requests.post(
            f"{BASE_URL}/rotate",
            json={"username": username, "new_password": candidate_password},
            headers=headers,
            timeout=2,
        )
        expected_status = 200 if is_valid else 401
        assert resp.status_code == expected_status, (
            f"Expected {expected_status} rotating {username!r} with token {token!r}, "
            f"got {resp.status_code}. Response: {resp.text}"
        )

        if is_valid:
            expected_current = new_password
        else:
            failed_candidates.append(candidate_password)

        verify(username, expected_current, 200)
        for failed_password in failed_candidates:
            if failed_password != expected_current:
                verify(username, failed_password, 401)

    verify(username, current_password, 401)
    verify(username, new_password, 200)
    return new_password


def test_http_service_behavior():
    # Preserve the original fixed assertions.
    try:
        resp = requests.get(
            f"{BASE_URL}/verify",
            auth=HTTPBasicAuth("admin", "hunter2"),
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to HTTP service at {BASE_URL}: {e}"
    assert resp.status_code == 200, f"Expected 200 OK for valid basic auth, got {resp.status_code}. Response: {resp.text}"
    assert_ok_body(resp)

    resp = requests.get(
        f"{BASE_URL}/verify",
        auth=HTTPBasicAuth("admin", "wrong"),
        timeout=2,
    )
    assert resp.status_code == 401, f"Expected 401 Unauthorized for invalid basic auth, got {resp.status_code}. Response: {resp.text}"

    admin_token = get_legacy_token("admin", "hunter2")
    rotate_payload = {"username": "admin", "new_password": "NewSecurePassword1!"}
    headers = {"X-Legacy-Token": admin_token}
    resp = requests.post(f"{BASE_URL}/rotate", json=rotate_payload, headers=headers, timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK for valid rotation, got {resp.status_code}. Response: {resp.text}"

    resp = requests.get(
        f"{BASE_URL}/verify",
        auth=HTTPBasicAuth("admin", "hunter2"),
        timeout=2,
    )
    assert resp.status_code == 401, f"Expected 401 Unauthorized for old password after rotation, got {resp.status_code}. Response: {resp.text}"

    resp = requests.get(
        f"{BASE_URL}/verify",
        auth=HTTPBasicAuth("admin", "NewSecurePassword1!"),
        timeout=2,
    )
    assert resp.status_code == 200, f"Expected 200 OK for new password after rotation, got {resp.status_code}. Response: {resp.text}"
    assert_ok_body(resp)

    rotate_payload_invalid = {"username": "db_user", "new_password": "Hacked"}
    headers_invalid = {"X-Legacy-Token": "invalidtoken"}
    resp = requests.post(
        f"{BASE_URL}/rotate",
        json=rotate_payload_invalid,
        headers=headers_invalid,
        timeout=2,
    )
    assert resp.status_code == 401, f"Expected 401 Unauthorized for invalid token rotation, got {resp.status_code}. Response: {resp.text}"
    verify("db_user", "secret", 200)
    verify("db_user", "Hacked", 401)

    # Exercise every recovered user with unpredictable passwords and token values.
    current = dict(EXPECTED_CREDS)
    current["admin"] = "NewSecurePassword1!"
    users = list(current)
    random.SystemRandom().shuffle(users)

    for username in users:
        verify(username, current[username], 200)
        verify(username, fresh_password("invalid_basic"), 401)
        current[username] = randomized_rotation_round(username, current[username], users)
        # A second rotation proves token validation follows the current in-memory password.
        current[username] = randomized_rotation_round(username, current[username], users)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
