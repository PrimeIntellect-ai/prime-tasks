#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3

DB_PATH = '/home/user/access_logs.db'
QUERY = "SELECT * FROM user_access WHERE status='failed' ORDER BY timestamp DESC LIMIT 10"

def test_audit_script_exists():
    path = '/home/user/audit.py'
    assert os.path.exists(path), f"Script {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

def test_index_created():
    db_path = '/home/user/access_logs.db'
    assert os.path.exists(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_access' AND name NOT LIKE 'sqlite_autoindex%'")
    indexes = c.fetchall()

    appropriate = []
    for (name,) in indexes:
        escaped = name.replace('"', '""')
        c.execute(f'PRAGMA index_info("{escaped}")')
        columns = [row[2].lower() for row in c.fetchall() if row[2] is not None]
        if columns[:2] == ['status', 'timestamp']:
            appropriate.append(name)
    conn.close()

    assert len(indexes) > 0, "No custom index was created on the 'user_access' table to optimize the query."
    assert appropriate, "No composite index beginning with (status, timestamp) was created for the failed-login query."

def test_query_plan_output():
    path = '/home/user/query_plan.txt'
    assert os.path.exists(path), f"Query plan output {path} does not exist."

    with open(path, 'r') as f:
        raw_content = f.read().strip()
    content = raw_content.upper()

    assert content, f"File {path} is empty."
    assert "USING INDEX" in content, f"Query plan does not indicate the use of an index. Content: {content}"

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_access' AND name NOT LIKE 'sqlite_autoindex%'")
    appropriate = []
    for (name,) in c.fetchall():
        escaped = name.replace('"', '""')
        c.execute(f'PRAGMA index_info("{escaped}")')
        columns = [row[2].lower() for row in c.fetchall() if row[2] is not None]
        if columns[:2] == ['status', 'timestamp']:
            appropriate.append(name)

    c.execute('EXPLAIN QUERY PLAN ' + QUERY)
    actual_rows = [tuple(row) for row in c.fetchall()]
    conn.close()

    details = [str(row[3]) for row in actual_rows]
    assert any(
        ('USING INDEX ' + name).upper() in detail.upper()
        for name in appropriate for detail in details
    ), f"The actual extraction query does not use an appropriate index. Plan: {actual_rows}"
    assert not any('USE TEMP B-TREE FOR ORDER BY' in detail.upper() for detail in details), \
        f"The actual extraction query still requires a temporary sort. Plan: {actual_rows}"

    accepted_exact_outputs = {
        '\n'.join(repr(row) for row in actual_rows),
        repr(actual_rows),
        '\n'.join('|'.join(str(value) for value in row) for row in actual_rows),
        '\n'.join('\t'.join(str(value) for value in row) for row in actual_rows),
        json.dumps([list(row) for row in actual_rows]),
        '\n'.join(json.dumps(list(row)) for row in actual_rows),
    }
    assert raw_content in accepted_exact_outputs, \
        f"{path} is not the exact EXPLAIN QUERY PLAN output for the extraction query. Expected rows: {actual_rows}"

def test_failed_logins_json():
    json_path = '/home/user/failed_logins.json'
    assert os.path.exists(json_path), f"Output file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    assert isinstance(data, list), f"JSON root must be an array, got {type(data).__name__}."
    assert len(data) == 10, f"Expected exactly 10 records, found {len(data)}."

    # Verify against the actual database truth
    db_path = '/home/user/access_logs.db'
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute("SELECT * FROM user_access WHERE status='failed' ORDER BY timestamp DESC LIMIT 10")
    expected_rows = [dict(row) for row in c.fetchall()]
    conn.close()

    assert len(expected_rows) == 10, "Database does not have enough failed records to verify against."

    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object."

        # Check keys
        expected_keys = {'id', 'username', 'ip_address', 'timestamp', 'status'}
        assert set(item.keys()) == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {set(item.keys())}."

        # Check values
        assert item['status'] == 'failed', f"Item at index {i} does not have status 'failed'."

        # Check descending order explicitly
        if i > 0:
            assert data[i-1]['timestamp'] >= data[i]['timestamp'], f"Timestamps are not strictly in descending order at index {i}."

        # Check exact match with database
        assert item == expected_rows[i], f"Item at index {i} does not match the expected database row."
TEST_EOF

script_ok=1
rm -f /home/user/query_plan.txt /home/user/failed_logins.json || script_ok=0

if [ "$script_ok" -eq 1 ] && [ -f /home/user/audit.py ]; then
    python3 - << 'PY_EOF' || script_ok=0
import sqlite3
path = '/home/user/access_logs.db'
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_access' AND name NOT LIKE 'sqlite_autoindex%'")
for (name,) in cur.fetchall():
    cur.execute('DROP INDEX "' + name.replace('"', '""') + '"')
conn.commit()
conn.close()
PY_EOF
    if [ "$script_ok" -eq 1 ]; then
        (cd /home/user && python3 /home/user/audit.py) || script_ok=0
    fi
else
    script_ok=0
fi

if [ "$script_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
