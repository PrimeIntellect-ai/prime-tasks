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
import sqlite3
import time
import uuid

import pytest
import requests

API_URL = "http://127.0.0.1:8080/api/backups"
TOKEN = "BRAVO-992-SECURE"
DYNAMIC_SUFFIX = uuid.uuid4().hex
DYNAMIC_TENANT = f"VERIFY-{DYNAMIC_SUFFIX}"
DISTRACTOR_TENANT = f"OTHER-{DYNAMIC_SUFFIX}"


def wait_for_service():
    """Wait briefly for the service to be ready."""
    for _ in range(10):
        if os.path.exists('/home/user/service_ready.txt'):
            return True
        time.sleep(0.5)
    return False


def get_expected_data(tenant_id, page, limit):
    conn = sqlite3.connect('/app/backup_catalog.db')
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM backups WHERE tenant_id=?", (tenant_id,))
    total_records = c.fetchone()[0]

    offset = (page - 1) * limit
    c.execute("""
        SELECT datastore_type, file_path, backup_timestamp, size_bytes
        FROM backups
        WHERE tenant_id=?
        ORDER BY backup_timestamp DESC
        LIMIT ? OFFSET ?
    """, (tenant_id, limit, offset))
    rows = c.fetchall()

    recovery_plan = {}
    for row in rows:
        ds_type = row[0]
        key = f"{ds_type}_backups"
        if key not in recovery_plan:
            recovery_plan[key] = []
        recovery_plan[key].append({
            "path": row[1],
            "timestamp": row[2],
            "size_mb": round(row[3] / (1024 * 1024), 2)
        })

    conn.close()

    return {
        "request_metadata": {
            "tenant_id": tenant_id,
            "page": page,
            "limit": limit,
            "total_records": total_records
        },
        "recovery_plan": recovery_plan
    }


@pytest.fixture(scope="session", autouse=True)
def add_unpredictable_catalog_records():
    conn = sqlite3.connect('/app/backup_catalog.db')
    rows = []
    for i in range(13):
        rows.append((
            DYNAMIC_TENANT,
            "postgres" if i % 2 == 0 else "mongo",
            f"/verification/{DYNAMIC_SUFFIX}/backup_{i}.dat",
            f"2042-07-{i + 1:02d}T{(i * 3) % 24:02d}:17:00Z",
            1048576 * (i + 1) + i * 13579
        ))
    rows.append((
        DISTRACTOR_TENANT,
        "postgres",
        f"/verification/{DYNAMIC_SUFFIX}/must_not_leak.dat",
        "2099-12-31T23:59:59Z",
        987654321
    ))
    conn.executemany(
        """INSERT INTO backups
           (tenant_id, datastore_type, file_path, backup_timestamp, size_bytes)
           VALUES (?, ?, ?, ?, ?)""",
        rows
    )
    conn.commit()
    conn.close()

    yield

    conn = sqlite3.connect('/app/backup_catalog.db')
    conn.execute("DELETE FROM backups WHERE tenant_id IN (?, ?)",
                 (DYNAMIC_TENANT, DISTRACTOR_TENANT))
    conn.commit()
    conn.close()


@pytest.fixture(autouse=True)
def check_service_ready():
    assert wait_for_service(), "Service ready signal file (/home/user/service_ready.txt) not found."


def test_unauthorized_no_token():
    response = requests.get(f"{API_URL}?tenant_id=ALPHA-774")
    assert response.status_code == 401, f"Expected 401 Unauthorized when missing token, got {response.status_code}. Response: {response.text}"


def test_unauthorized_wrong_token():
    headers = {"Authorization": "Bearer WRONG-TOKEN"}
    response = requests.get(f"{API_URL}?tenant_id=ALPHA-774", headers=headers)
    assert response.status_code == 401, f"Expected 401 Unauthorized with wrong token, got {response.status_code}. Response: {response.text}"


def test_valid_request_schema_and_data():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    tenant_id = "ALPHA-774"
    page = 1
    limit = 2

    response = requests.get(f"{API_URL}?tenant_id={tenant_id}&page={page}&limit={limit}", headers=headers)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    expected_data = get_expected_data(tenant_id, page, limit)

    assert data == expected_data, f"JSON response does not match expected schema/data.\nExpected: {expected_data}\nGot: {data}"


def test_valid_request_page_2():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    tenant_id = "ALPHA-774"
    page = 2
    limit = 2

    response = requests.get(f"{API_URL}?tenant_id={tenant_id}&page={page}&limit={limit}", headers=headers)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    data = response.json()
    expected_data = get_expected_data(tenant_id, page, limit)

    assert data == expected_data, f"JSON response does not match expected schema/data for page 2.\nExpected: {expected_data}\nGot: {data}"


def test_dynamic_tenant_with_default_pagination():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    response = requests.get(
        API_URL,
        params={"tenant_id": DYNAMIC_TENANT},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    expected_data = get_expected_data(DYNAMIC_TENANT, 1, 10)
    assert data == expected_data, (
        f"Default pagination or dynamic tenant filtering is incorrect.\n"
        f"Expected: {expected_data}\nGot: {data}"
    )


def test_dynamic_tenant_general_pagination():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    for page, limit in [(1, 1), (2, 4), (3, 5), (6, 3)]:
        response = requests.get(
            API_URL,
            params={"tenant_id": DYNAMIC_TENANT, "page": page, "limit": limit},
            headers=headers,
        )
        assert response.status_code == 200, (
            f"Expected 200 for page={page}, limit={limit}; got "
            f"{response.status_code}: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Response: {response.text}")

        expected_data = get_expected_data(DYNAMIC_TENANT, page, limit)
        assert data == expected_data, (
            f"Dynamic pagination mismatch for page={page}, limit={limit}.\n"
            f"Expected: {expected_data}\nGot: {data}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
