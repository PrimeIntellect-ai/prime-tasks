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
import csv
import os
import random
import re
import sqlite3
from pathlib import Path

import requests

DB_PATH = "/home/user/analytics.db"
URL = "http://127.0.0.1:9090/insights"
VALID_HEADERS = {"X-API-Token": "sierra-tango-99"}
EXACT_KEYS = {"customer_id", "rolling_amount", "latest_call_duration"}


def api_get(headers=VALID_HEADERS):
    try:
        return requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to API: {exc}"


def assert_schema(data):
    assert isinstance(data, list), "Expected JSON response to be a list"
    for item in data:
        assert isinstance(item, dict), "Each item in the list must be a JSON object"
        assert "customer_id" in item, "Missing 'customer_id' in response object"
        assert "rolling_amount" in item, "Missing 'rolling_amount' in response object"
        assert "latest_call_duration" in item, "Missing 'latest_call_duration' in response object"
        assert set(item) == EXACT_KEYS, f"Response object must have exactly {EXACT_KEYS}, got {set(item)}"
        assert isinstance(item["customer_id"], int) and not isinstance(item["customer_id"], bool), "'customer_id' must be an integer"
        assert isinstance(item["rolling_amount"], (int, float)) and not isinstance(item["rolling_amount"], bool), "'rolling_amount' must be a float/int"
        assert isinstance(item["rolling_amount"], float), "'rolling_amount' must be a float"
        assert isinstance(item["latest_call_duration"], int) and not isinstance(item["latest_call_duration"], bool), "'latest_call_duration' must be an integer"


def expected_from_csv():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("CREATE TABLE transactions (tx_id TEXT, customer_id INTEGER, tx_date TEXT, amount REAL)")
    cur.execute("CREATE TABLE calls (call_id TEXT, customer_id INTEGER, call_date TEXT, duration_seconds INTEGER)")

    with open('/home/user/transactions.csv', newline='') as f:
        for row in csv.DictReader(f):
            cur.execute("INSERT INTO transactions VALUES (?, ?, ?, ?)",
                        (row['tx_id'], int(row['customer_id']), row['tx_date'], float(row['amount'])))
    with open('/home/user/calls.csv', newline='') as f:
        for row in csv.DictReader(f):
            cur.execute("INSERT INTO calls VALUES (?, ?, ?, ?)",
                        (row['call_id'], int(row['customer_id']), row['call_date'], int(row['duration_seconds'])))

    query = """
    WITH latest_tx AS (
        SELECT customer_id, MAX(tx_date) AS max_tx_date
        FROM transactions GROUP BY customer_id
    ),
    rolling_sums AS (
        SELECT t.customer_id, SUM(t.amount) AS rolling_amount
        FROM transactions t
        JOIN latest_tx lt ON t.customer_id = lt.customer_id
        WHERE t.tx_date >= date(lt.max_tx_date, '-7 days')
          AND t.tx_date <= lt.max_tx_date
        GROUP BY t.customer_id
    ),
    latest_call AS (
        SELECT customer_id, duration_seconds AS latest_call_duration
        FROM (
            SELECT customer_id, duration_seconds,
                   ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY call_date DESC) AS rn
            FROM calls
        ) WHERE rn = 1
    )
    SELECT r.customer_id, r.rolling_amount, l.latest_call_duration
    FROM rolling_sums r JOIN latest_call l ON r.customer_id = l.customer_id
    """
    rows = cur.execute(query).fetchall()
    conn.close()
    return {row['customer_id']: {
        'rolling_amount': float(row['rolling_amount']),
        'latest_call_duration': int(row['latest_call_duration'])
    } for row in rows}


def test_database_exists_and_contains_ingested_csv_data():
    assert os.path.isfile(DB_PATH), f"Database not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert {'customers', 'transactions', 'calls'} <= tables, f"Missing required tables; found {tables}"

        with open('/home/user/customers.csv', newline='') as f:
            expected_customers = {(int(r['customer_id']), r['name'], r['signup_date']) for r in csv.DictReader(f)}
        with open('/home/user/transactions.csv', newline='') as f:
            expected_transactions = {(int(r['tx_id']), int(r['customer_id']), r['tx_date'], float(r['amount'])) for r in csv.DictReader(f)}
        with open('/home/user/calls.csv', newline='') as f:
            expected_calls = {(int(r['call_id']), int(r['customer_id']), r['call_date'], int(r['duration_seconds'])) for r in csv.DictReader(f)}

        actual_customers = set(conn.execute("SELECT customer_id, name, signup_date FROM customers"))
        actual_transactions = set(conn.execute("SELECT tx_id, customer_id, tx_date, amount FROM transactions"))
        actual_calls = set(conn.execute("SELECT call_id, customer_id, call_date, duration_seconds FROM calls"))
        assert actual_customers == expected_customers, "customers table does not match customers.csv"
        assert actual_transactions == expected_transactions, "transactions table does not match transactions.csv"
        assert actual_calls == expected_calls, "calls table does not match calls.csv"
    finally:
        conn.close()


def indexed_columns(conn, table):
    result = []
    for index_row in conn.execute(f"PRAGMA index_list('{table}')"):
        name = index_row[1]
        cols = [r[2] for r in conn.execute(f"PRAGMA index_info('{name}')")]
        result.append(cols)
    return result


def test_join_and_temporal_indexes_exist():
    conn = sqlite3.connect(DB_PATH)
    try:
        for table, date_col in [('transactions', 'tx_date'), ('calls', 'call_date')]:
            indexes = indexed_columns(conn, table)
            assert any('customer_id' in cols and date_col in cols and cols.index('customer_id') < cols.index(date_col)
                       for cols in indexes), f"{table} needs an index ordered by customer_id then {date_col}; found {indexes}"
    finally:
        conn.close()


def test_server_source_contains_rolling_window_function():
    candidates = []
    for root in ('/home/user', '/app'):
        if os.path.isdir(root):
            candidates.extend(Path(root).rglob('*.py'))

    # Include Python files explicitly named in command lines of running processes.
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            cwd = Path(os.readlink(proc / 'cwd'))
            for arg in args:
                text = arg.decode(errors='ignore')
                if text.endswith('.py'):
                    path = Path(text)
                    candidates.append(path if path.is_absolute() else cwd / path)
        except (OSError, PermissionError):
            pass

    source = ""
    seen = set()
    for path in candidates:
        try:
            resolved = str(path.resolve())
            if resolved in seen or resolved == '/tmp/test_final_state.py':
                continue
            seen.add(resolved)
            source += "\n" + path.read_text(errors='ignore')
        except (OSError, PermissionError):
            pass

    assert re.search(r"\bSUM\s*\([^;]*?\)\s*OVER\s*\(", source, re.IGNORECASE | re.DOTALL), \
        "Server/ETL source must calculate the rolling amount with a SQL SUM(...) OVER(...) window function"


def test_api_invalid_token():
    response = api_get({"X-API-Token": "invalid-token"})
    assert response.status_code in (401, 403), f"Expected 401 or 403 for invalid token, got {response.status_code}"


def test_api_valid_token_and_schema():
    response = api_get()
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code} with body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        assert False, "API did not return valid JSON"
    assert_schema(data)


def test_api_correctness():
    expected_data = expected_from_csv()
    response = api_get()
    assert response.status_code == 200
    actual_data = response.json()
    actual_dict = {item['customer_id']: item for item in actual_data}
    assert len(actual_dict) == len(expected_data), f"Expected {len(expected_data)} customers, got {len(actual_dict)}"
    assert len(actual_data) == len(actual_dict), "API returned duplicate customer_id values"
    for cid, exp in expected_data.items():
        assert cid in actual_dict, f"Missing customer {cid} in API response"
        act = actual_dict[cid]
        assert abs(act['rolling_amount'] - exp['rolling_amount']) < 1e-5, f"Incorrect rolling_amount for customer {cid}: expected {exp['rolling_amount']}, got {act['rolling_amount']}"
        assert act['latest_call_duration'] == exp['latest_call_duration'], f"Incorrect latest_call_duration for customer {cid}: expected {exp['latest_call_duration']}, got {act['latest_call_duration']}"


def test_api_executes_query_against_database_with_seven_day_window():
    # Randomized rows prevent a server from passing by returning fixture-specific hardcoded JSON.
    base = 700000 + random.SystemRandom().randrange(100000)
    target, tx_only, call_only = base, base + 1, base + 2
    a = random.SystemRandom().randrange(1100, 4900) / 100.0
    b = random.SystemRandom().randrange(5100, 8900) / 100.0
    excluded = random.SystemRandom().randrange(9100, 12900) / 100.0
    latest_duration = random.SystemRandom().randrange(401, 999)

    conn = sqlite3.connect(DB_PATH, timeout=5)
    try:
        conn.executemany("INSERT INTO customers(customer_id, name, signup_date) VALUES (?, ?, ?)", [
            (target, 'Verifier Target', '2024-01-01'),
            (tx_only, 'Verifier Tx Only', '2024-01-01'),
            (call_only, 'Verifier Call Only', '2024-01-01')])
        conn.executemany("INSERT INTO transactions(tx_id, customer_id, tx_date, amount) VALUES (?, ?, ?, ?)", [
            (base * 10 + 1, target, '2024-01-02', excluded),  # eight days before latest: excluded
            (base * 10 + 2, target, '2024-01-03', a),         # exactly seven days before: included
            (base * 10 + 3, target, '2024-01-10', b),
            (base * 10 + 4, tx_only, '2024-01-10', 17.25)])
        conn.executemany("INSERT INTO calls(call_id, customer_id, call_date, duration_seconds) VALUES (?, ?, ?, ?)", [
            (base * 10 + 5, target, '2024-01-05', latest_duration - 1),
            (base * 10 + 6, target, '2024-01-11', latest_duration),
            (base * 10 + 7, call_only, '2024-01-11', 123)])
        conn.commit()

        response = api_get()
        assert response.status_code == 200, response.text
        data = response.json()
        assert_schema(data)
        by_id = {item['customer_id']: item for item in data}
        assert target in by_id, "API did not query the newly inserted eligible customer"
        assert abs(by_id[target]['rolling_amount'] - (a + b)) < 1e-5, \
            "Rolling sum must include the seven-day boundary and exclude older transactions"
        assert by_id[target]['latest_call_duration'] == latest_duration, "API did not select the most recent call"
        assert tx_only not in by_id, "Customer without calls must be excluded"
        assert call_only not in by_id, "Customer without transactions must be excluded"
    finally:
        try:
            conn.execute("DELETE FROM transactions WHERE customer_id IN (?, ?, ?)", (target, tx_only, call_only))
            conn.execute("DELETE FROM calls WHERE customer_id IN (?, ?, ?)", (target, tx_only, call_only))
            conn.execute("DELETE FROM customers WHERE customer_id IN (?, ?, ?)", (target, tx_only, call_only))
            conn.commit()
        finally:
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
