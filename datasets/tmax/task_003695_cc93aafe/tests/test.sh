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
# test_final_state.py

import secrets
import sqlite3
import requests
import pytest

PORT = 8123
TOKEN = "AlphaBravo123"
URL = f"http://127.0.0.1:{PORT}/api/v1/datasets/stats"

def get_expected_data():
    """Derive the expected JSON response from the current state of the database."""
    conn = sqlite3.connect('/app/datasets.db')
    c = conn.cursor()
    c.execute('''
        SELECT c.name, a.full_name, m.metric_value
        FROM tbl_collections c
        JOIN tbl_authors a ON c.author_id = a.id
        LEFT JOIN tbl_metrics m ON m.col_id = c.id
    ''')
    rows = c.fetchall()
    conn.close()

    data = {}
    for c_name, a_name, m_val in rows:
        if c_name not in data:
            data[c_name] = {'author': a_name, 'metrics': []}
        if m_val is not None:
            data[c_name]['metrics'].append(m_val)

    results = []
    for c_name in sorted(data.keys()):
        metrics = sorted(data[c_name]['metrics'], reverse=True)[:2]
        results.append({
            "dataset_name": c_name,
            "author_name": data[c_name]['author'],
            "top_metrics": metrics
        })
    return {"results": results}

def test_api_no_auth():
    """Test that the API returns 401 when no authorization header is provided."""
    try:
        resp = requests.get(URL, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")

    assert resp.status_code == 401, f"Expected 401 Unauthorized without token, got {resp.status_code}. Response: {resp.text}"

def test_api_invalid_auth():
    """Test that the API returns 401 when an invalid authorization header is provided."""
    headers = {"Authorization": "Bearer InvalidToken"}
    try:
        resp = requests.get(URL, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")

    assert resp.status_code == 401, f"Expected 401 Unauthorized with invalid token, got {resp.status_code}. Response: {resp.text}"

def test_api_valid_auth_and_data():
    """Test that the API returns 200 and the correct JSON data when a valid token is provided."""
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        resp = requests.get(URL, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK with valid token, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    expected = get_expected_data()
    assert data == expected, f"API response data did not match expected data.\nExpected: {expected}\nGot: {data}"

def test_api_uses_current_database_contents():
    """Add unpredictable records and verify that the API derives its response from SQLite."""
    suffix = secrets.token_hex(8)
    author_name = f"Dynamic Author {suffix}"
    collection_names = [
        f"Dynamic Empty {suffix}",
        f"Dynamic Single {suffix}",
        f"Dynamic Ranked {suffix}",
    ]
    value_base = secrets.randbelow(900000) + 100000
    ranked_values = [
        float(value_base) + 0.125,
        float(value_base) + 20.5,
        float(value_base) + 10.25,
        float(value_base) - 5.75,
    ]
    single_value = float(value_base) + 3.875

    conn = sqlite3.connect('/app/datasets.db')
    try:
        c = conn.cursor()
        author_id = c.execute('SELECT COALESCE(MAX(id), 0) + 1000 FROM tbl_authors').fetchone()[0]
        collection_id = c.execute('SELECT COALESCE(MAX(id), 0) + 1000 FROM tbl_collections').fetchone()[0]
        metric_id = c.execute('SELECT COALESCE(MAX(id), 0) + 1000 FROM tbl_metrics').fetchone()[0]

        c.execute('INSERT INTO tbl_authors (id, full_name) VALUES (?, ?)', (author_id, author_name))
        for offset, name in enumerate(collection_names):
            c.execute(
                'INSERT INTO tbl_collections (id, author_id, name) VALUES (?, ?, ?)',
                (collection_id + offset, author_id, name),
            )
        c.execute(
            'INSERT INTO tbl_metrics (id, col_id, metric_value) VALUES (?, ?, ?)',
            (metric_id, collection_id + 1, single_value),
        )
        for offset, value in enumerate(ranked_values, start=1):
            c.execute(
                'INSERT INTO tbl_metrics (id, col_id, metric_value) VALUES (?, ?, ?)',
                (metric_id + offset, collection_id + 2, value),
            )
        conn.commit()
    finally:
        conn.close()

    try:
        headers = {"Authorization": f"Bearer {TOKEN}"}
        try:
            resp = requests.get(URL, headers=headers, timeout=5)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to API after database mutation: {e}")

        assert resp.status_code == 200, f"Expected 200 OK after database mutation, got {resp.status_code}. Response: {resp.text}"
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response after database mutation is not valid JSON: {resp.text}")

        expected = get_expected_data()
        assert data == expected, f"API did not reflect the current database contents.\nExpected: {expected}\nGot: {data}"
    finally:
        cleanup = sqlite3.connect('/app/datasets.db')
        try:
            cleanup.execute('DELETE FROM tbl_metrics WHERE col_id BETWEEN ? AND ?', (collection_id, collection_id + 2))
            cleanup.execute('DELETE FROM tbl_collections WHERE id BETWEEN ? AND ?', (collection_id, collection_id + 2))
            cleanup.execute('DELETE FROM tbl_authors WHERE id = ?', (author_id,))
            cleanup.commit()
        finally:
            cleanup.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
