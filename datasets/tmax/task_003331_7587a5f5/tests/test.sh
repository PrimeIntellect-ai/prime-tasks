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
import sqlite3

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080/api/audit/summary"
AUTH_HEADER = {"Authorization": "Bearer ComplianceAudit2024"}
DB_PATH = "/home/user/audit.db"


def get_expected_totals(emp_id):
    """Derive the expected totals directly from the database."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT COALESCE(SUM(amount), 0) FROM transactions WHERE emp_id = ?", (emp_id,))
    tx_amount = c.fetchone()[0]
    c.execute("SELECT COUNT(*) FROM access_logs WHERE emp_id = ?", (emp_id,))
    access_count = c.fetchone()[0]
    conn.close()
    return tx_amount, access_count


def install_random_challenges():
    """Add unpredictable employees after the submitted service has started."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    ids = []
    while len(ids) < 4:
        emp_id = 100000 + secrets.randbelow(900000000)
        c.execute("SELECT 1 FROM employees WHERE id = ?", (emp_id,))
        if c.fetchone() is None and emp_id not in ids:
            ids.append(emp_id)

    cents = [1000 + secrets.randbelow(900000) for _ in range(5)]
    challenge_data = [
        (ids[0], [cents[0] / 100.0, cents[1] / 100.0], 3),
        (ids[1], [cents[2] / 100.0], 0),
        (ids[2], [], 2),
        (ids[3], [cents[3] / 100.0, cents[4] / 100.0], 4),
    ]

    for emp_id, amounts, access_count in challenge_data:
        c.execute("INSERT INTO employees (id, name) VALUES (?, ?)",
                  (emp_id, f"VerifierChallenge-{secrets.token_hex(8)}"))
        for amount in amounts:
            c.execute("INSERT INTO transactions (emp_id, amount) VALUES (?, ?)",
                      (emp_id, amount))
        for index in range(access_count):
            c.execute("INSERT INTO access_logs (emp_id, system) VALUES (?, ?)",
                      (emp_id, f"VerifierSystem-{index}-{secrets.token_hex(4)}"))

    conn.commit()
    conn.close()
    return ids


CHALLENGE_IDS = install_random_challenges()


@pytest.fixture(scope="session", autouse=True)
def cleanup_challenges():
    yield
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    for emp_id in CHALLENGE_IDS:
        c.execute("DELETE FROM transactions WHERE emp_id = ?", (emp_id,))
        c.execute("DELETE FROM access_logs WHERE emp_id = ?", (emp_id,))
        c.execute("DELETE FROM employees WHERE id = ?", (emp_id,))
    conn.commit()
    conn.close()


def assert_summary(emp_id):
    expected_tx, expected_access = get_expected_totals(emp_id)

    try:
        resp = requests.get(BASE_URL, params={"emp_id": str(emp_id)},
                            headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert resp.status_code == 200, (
        f"Expected 200 OK for emp_id={emp_id}, got {resp.status_code}. "
        f"Response: {resp.text}"
    )

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert data.get("emp_id") == emp_id, (
        f"Expected emp_id {emp_id}, got {data.get('emp_id')}"
    )

    actual_tx = data.get("total_tx_amount", 0)
    assert isinstance(actual_tx, (int, float)), (
        f"total_tx_amount must be numeric, got {actual_tx!r}"
    )
    assert abs(actual_tx - expected_tx) < 0.01, (
        f"Expected total_tx_amount {expected_tx}, got {actual_tx} "
        "(possible cross-join bug?)"
    )

    actual_access = data.get("total_access_count")
    assert actual_access == expected_access, (
        f"Expected total_access_count {expected_access}, got {actual_access} "
        "(possible cross-join bug?)"
    )


def test_auth_missing():
    """Ensure the endpoint returns 401 when Authorization header is missing."""
    try:
        resp = requests.get(f"{BASE_URL}?emp_id=1", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert resp.status_code == 401, (
        f"Expected 401 Unauthorized for missing auth, got {resp.status_code}. "
        f"Response: {resp.text}"
    )


def test_auth_invalid():
    """Ensure the endpoint returns 401 when Authorization header is incorrect."""
    headers = {"Authorization": "Bearer WrongToken123"}
    try:
        resp = requests.get(f"{BASE_URL}?emp_id=1", headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert resp.status_code == 401, (
        f"Expected 401 Unauthorized for invalid auth, got {resp.status_code}. "
        f"Response: {resp.text}"
    )


@pytest.mark.parametrize("emp_id", [1, 2, 3])
def test_valid_employee_summaries(emp_id):
    """Test the original fixture employees and aggregation behavior."""
    assert_summary(emp_id)


@pytest.mark.parametrize("emp_id", CHALLENGE_IDS)
def test_runtime_generated_employee_summaries(emp_id):
    """Require answers for unpredictable database rows added after service startup."""
    assert_summary(emp_id)


def test_sql_injection_resilience():
    """Test that the endpoint is resilient to basic SQL injection on emp_id."""
    payload = "1 OR 1=1"
    try:
        resp = requests.get(BASE_URL, params={"emp_id": payload},
                            headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    if resp.status_code in [400, 404, 422]:
        return

    if resp.status_code == 200:
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp.text}")

        actual_tx = data.get("total_tx_amount", 0)
        assert isinstance(actual_tx, (int, float)), (
            f"total_tx_amount must be numeric, got {actual_tx!r}"
        )
        assert actual_tx < 200, (
            f"SQL injection appears successful! Aggregated amount is {actual_tx}, "
            "expected <= 150.50"
        )
    else:
        pytest.fail(
            f"Unexpected status code {resp.status_code} for SQL injection test. "
            "Expected 400/404/422 or a safe 200."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
