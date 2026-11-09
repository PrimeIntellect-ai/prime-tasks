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
import secrets
import sqlite3
import subprocess
import sys

import pytest
import requests

DB_PATH = "/app/services/log-ingest/logs.db"
SCRIPT_PATH = "/home/user/decrypt_logs.py"
OUTPUT_PATH = "/home/user/decrypted_logs.json"
EXPORT_INPUT_PATH = "/home/user/encrypted_logs.json"
TOKEN_HEADER = {"Authorization": "Bearer COMPLIANCE_SECURE_TOKEN"}


def encrypt(text):
    key = "S3cr3t"
    return "".join(f"{ord(c) ^ ord(key[i % len(key)]):02X}" for i, c in enumerate(text))


def decrypt(hex_text):
    key = "S3cr3t"
    raw = [chr(int(hex_text[i:i + 2], 16)) for i in range(0, len(hex_text), 2)]
    return "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(raw))


@pytest.fixture(scope="session", autouse=True)
def verifier_state():
    marker = secrets.token_hex(8)
    user = "audit_user_" + marker
    action = "audit_action_" + marker

    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        next_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM logs").fetchone()[0]
        conn.execute(
            "INSERT INTO logs (id, user, action) VALUES (?, ?, ?)",
            (next_id, encrypt(user), encrypt(action)),
        )
        conn.commit()
    finally:
        conn.close()

    try:
        response = requests.get(
            "http://127.0.0.1:5002/export",
            cookies={"admin_session": "admin_cookie_v1_S3cr3t"},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to retrieve encrypted export from log-ingest: {exc}")
    assert response.status_code == 200, response.text
    encrypted_export = response.json()
    assert isinstance(encrypted_export, list)

    expected = []
    for row in encrypted_export:
        expected.append({
            "id": row["id"],
            "user": decrypt(row["user"]),
            "action": decrypt(row["action"]),
        })

    assert any(str(row["id"]) == str(next_id) for row in expected)
    with open(EXPORT_INPUT_PATH, "w") as f:
        json.dump(encrypted_export, f)

    yield {
        "id": next_id,
        "user": user,
        "action": action,
        "expected_logs": expected,
        "encrypted_json": json.dumps(encrypted_export),
    }


def output_matches(expected):
    try:
        with open(OUTPUT_PATH) as f:
            actual = json.load(f)
        if not isinstance(actual, list) or len(actual) != len(expected):
            return False
        actual_by_id = {str(row["id"]): row for row in actual}
        return all(
            str(row["id"]) in actual_by_id
            and actual_by_id[str(row["id"])].get("user") == row["user"]
            and actual_by_id[str(row["id"])].get("action") == row["action"]
            for row in expected
        )
    except Exception:
        return False


def test_decrypt_script_exists():
    """Verify that the decrypt script was written."""
    assert os.path.isfile(SCRIPT_PATH), f"Expected file {SCRIPT_PATH} is missing."


def test_decrypted_logs_exist_and_are_correct(verifier_state):
    """Execute the submitted script and validate its decryption of the current export."""
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    env = os.environ.copy()
    env["ENCRYPTED_LOGS_PATH"] = EXPORT_INPUT_PATH
    attempts = []

    # Support both a self-contained script and a script accepting the export path.
    for command in ([sys.executable, SCRIPT_PATH], [sys.executable, SCRIPT_PATH, EXPORT_INPUT_PATH]):
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        try:
            result = subprocess.run(
                command,
                input=verifier_state["encrypted_json"],
                text=True,
                capture_output=True,
                timeout=15,
                env=env,
            )
            attempts.append(
                f"{' '.join(command)}: exit={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
        except subprocess.TimeoutExpired:
            attempts.append(f"{' '.join(command)}: timed out")
            continue

        if result.returncode == 0 and output_matches(verifier_state["expected_logs"]):
            break

    assert os.path.isfile(OUTPUT_PATH), (
        f"Expected file {OUTPUT_PATH} is missing after executing the script. " + " | ".join(attempts)
    )

    with open(OUTPUT_PATH) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "Decrypted logs should be a JSON array."
    assert output_matches(verifier_state["expected_logs"]), (
        "The script's decrypted output does not match the current encrypted export. " + " | ".join(attempts)
    )


def test_secure_proxy_authorized():
    """Test that the secure proxy returns the decrypted known log entry."""
    url = "http://127.0.0.1:9000/compliance?id=1"
    try:
        response = requests.get(url, headers=TOKEN_HEADER, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to secure proxy at {url}: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from proxy, got: {response.text}")

    assert "id" in data, "Response JSON missing 'id' field."
    assert str(data["id"]) == "1", f"Expected id 1, got {data['id']}"
    assert "action" in data, "Response JSON missing 'action' field."
    assert "user" in data, "Response JSON missing 'user' field."
    assert data["action"] == "login", f"Expected decrypted action 'login', got {data['action']!r}"
    assert data["user"] == "admin", f"Expected decrypted user 'admin', got {data['user']!r}"


def test_secure_proxy_uses_current_log_data(verifier_state):
    """Reject a proxy that hardcodes only the original id=1 response."""
    url = f"http://127.0.0.1:9000/compliance?id={verifier_state['id']}"
    try:
        response = requests.get(url, headers=TOKEN_HEADER, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to secure proxy at {url}: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert str(data.get("id")) == str(verifier_state["id"])
    assert data.get("user") == verifier_state["user"]
    assert data.get("action") == verifier_state["action"]


def test_secure_proxy_unauthorized():
    """Test that the secure proxy rejects unauthorized requests."""
    url = "http://127.0.0.1:9000/compliance?id=1"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to secure proxy at {url}: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing token, got {response.status_code}."

    try:
        response = requests.get(
            url,
            headers={"Authorization": "Bearer INVALID_TOKEN"},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to secure proxy at {url}: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for invalid token, got {response.status_code}."


def test_sql_injection_remediated(verifier_state):
    """Test SQL injection with multiple database rows so the original endpoint fails."""
    url = "http://127.0.0.1:5002/search"
    params = {"user": "admin' OR 1=1 --"}

    try:
        response = requests.get(url, params=params, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to log-ingest service at {url}: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from search endpoint, got: {response.text}")

    assert isinstance(data, list), "Expected JSON response to be a list."
    assert len(data) <= 1, "SQL injection appears to still be present; returned multiple records for an invalid username."
    assert data == [], "An injection payload must be treated as a literal value and return no records."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
