#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

EXPECTED=/root/verifier_expected.json
printf '0\n' > /tmp/fixture_ok
printf '0\n' > /tmp/migrate_artifact_ok
printf '0\n' > /tmp/emulator_artifact_ok
printf '0\n' > /tmp/migrate_execution_ok
printf '0\n' > /tmp/emulator_execution_ok
printf '0\n' > /tmp/migration_behavior_ok

if [ -f /home/user/migrate.py ] && [ ! -L /home/user/migrate.py ]; then
    printf '1\n' > /tmp/migrate_artifact_ok
fi
if [ -f /home/user/emulator.py ] && [ ! -L /home/user/emulator.py ]; then
    printf '1\n' > /tmp/emulator_artifact_ok
fi

if python3 - <<'PY'
import json
import os
import sqlite3
import uuid

DB_PATH = '/home/user/api.db'
DSL_PATH = '/home/user/queries.dsl'
EXPECTED = '/root/verifier_expected.json'

def payload(status, body):
    return f"status={status},body={body}".encode('utf-16le').hex()

nonce = uuid.uuid4().hex
rows = [
    (17, f"/verify/{nonce}/alpha", 201, f'{{"token":"{nonce[:10]}","note":"a,b=c"}}'),
    (29, f"/verify/{nonce}/beta", 418, f'{{"message":"teapot-{nonce[10:18]}"}}'),
    (44, f"/verify/{nonce}/unicode", 204, f'Unicode café Ω {nonce[18:24]}'),
    (63, f"/verify/{nonce}/server", 503, f'backend=down,request={nonce[24:]}'),
]
missing = f"/verify/{nonce}/missing"
dsl_pairs = [
    (rows[0][1], rows[0][2]),
    (rows[1][1], 200),
    (missing, 404),
    (rows[2][1], rows[2][2]),
    (rows[3][1], 502),
]
dsl = ''.join(f"EXEC {endpoint}\nASSERT_STATUS {status}\n" for endpoint, status in dsl_pairs)
expected_log = []
row_map = {row[1]: (row[2], row[3]) for row in rows}
for endpoint, asserted in dsl_pairs:
    if endpoint not in row_map:
        expected_log.append(f"[{endpoint}] ERROR: not found\n")
    else:
        actual, body = row_map[endpoint]
        if actual == asserted:
            expected_log.append(f"[{endpoint}] PASS: {body}\n")
        else:
            expected_log.append(f"[{endpoint}] FAIL: expected {asserted}, got {actual}\n")

if os.path.exists(DB_PATH):
    os.remove(DB_PATH)
conn = sqlite3.connect(DB_PATH)
conn.execute('CREATE TABLE mocks_v1 (id INTEGER PRIMARY KEY, endpoint TEXT, payload_encoded TEXT)')
v1 = [(row_id, endpoint, payload(status, body)) for row_id, endpoint, status, body in rows]
conn.executemany('INSERT INTO mocks_v1 VALUES (?, ?, ?)', v1)
conn.commit()
conn.close()
with open(DSL_PATH, 'w', encoding='utf-8') as f:
    f.write(dsl)
with open(EXPECTED, 'w', encoding='utf-8') as f:
    json.dump({'v1': v1, 'v2': rows, 'dsl': dsl, 'log': expected_log}, f)
os.chmod(EXPECTED, 0o600)
os.chown(DB_PATH, 1000, 1000)
os.chown(DSL_PATH, 1000, 1000)
PY
then
    printf '1\n' > /tmp/fixture_ok
fi

if [ "$(cat /tmp/fixture_ok)" = 1 ] && [ "$(cat /tmp/migrate_artifact_ok)" = 1 ]; then
    if runuser -u user -- python3 /home/user/migrate.py; then
        printf '1\n' > /tmp/migrate_execution_ok
    fi
fi

if [ "$(cat /tmp/migrate_execution_ok)" = 1 ]; then
    if python3 - <<'PY'
import json
import sqlite3

with open('/root/verifier_expected.json', encoding='utf-8') as f:
    expected = json.load(f)
with open('/home/user/queries.dsl', encoding='utf-8') as f:
    assert f.read() == expected['dsl']
conn = sqlite3.connect('/home/user/api.db')
v1 = conn.execute('SELECT id, endpoint, payload_encoded FROM mocks_v1 ORDER BY id').fetchall()
v2 = conn.execute('SELECT id, endpoint, status_code, response_body FROM mocks_v2 ORDER BY id').fetchall()
conn.close()
assert v1 == [tuple(row) for row in expected['v1']]
assert v2 == [tuple(row) for row in expected['v2']]
PY
    then
        printf '1\n' > /tmp/migration_behavior_ok
    fi
fi

rm -f /home/user/test_results.log
if [ "$(cat /tmp/fixture_ok)" = 1 ] && [ "$(cat /tmp/emulator_artifact_ok)" = 1 ]; then
    if runuser -u user -- python3 /home/user/emulator.py; then
        printf '1\n' > /tmp/emulator_execution_ok
    fi
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import pytest

DB_PATH = '/home/user/api.db'
DSL_PATH = '/home/user/queries.dsl'
LOG_PATH = '/home/user/test_results.log'
EXPECTED_PATH = '/root/verifier_expected.json'

def marker(path):
    try:
        with open(path) as f:
            return f.read().strip() == '1'
    except OSError:
        return False

def get_expected_v2_data():
    if not os.path.exists(DB_PATH):
        return []
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    try:
        c.execute("SELECT id, endpoint, payload_encoded FROM mocks_v1 ORDER BY id")
        rows = c.fetchall()
    except sqlite3.OperationalError:
        rows = []
    finally:
        conn.close()

    expected = []
    for row in rows:
        row_id, endpoint, payload_encoded = row
        decoded = bytes.fromhex(payload_encoded).decode('utf-16le')
        parts = decoded.split(',', 1)
        status = int(parts[0].split('=')[1])
        body = parts[1].split('=', 1)[1]
        expected.append((row_id, endpoint, status, body))
    return expected

def test_required_scripts_were_executed_and_behaved_correctly():
    assert marker('/tmp/fixture_ok'), 'Verifier fixture setup failed.'
    assert marker('/tmp/migrate_artifact_ok'), '/home/user/migrate.py must be a regular, non-symlink file.'
    assert marker('/tmp/emulator_artifact_ok'), '/home/user/emulator.py must be a regular, non-symlink file.'
    assert marker('/tmp/migrate_execution_ok'), 'migrate.py did not execute successfully.'
    assert marker('/tmp/migration_behavior_ok'), 'migrate.py did not correctly migrate the independent fixture.'
    assert marker('/tmp/emulator_execution_ok'), 'emulator.py did not execute successfully.'

def test_independent_inputs_and_outputs():
    with open(EXPECTED_PATH, encoding='utf-8') as f:
        expected = json.load(f)
    with open(DSL_PATH, encoding='utf-8') as f:
        assert f.read() == expected['dsl'], 'queries.dsl was modified by the submission.'

    conn = sqlite3.connect(DB_PATH)
    v1 = conn.execute('SELECT id, endpoint, payload_encoded FROM mocks_v1 ORDER BY id').fetchall()
    v2 = conn.execute('SELECT id, endpoint, status_code, response_body FROM mocks_v2 ORDER BY id').fetchall()
    conn.close()
    assert v1 == [tuple(row) for row in expected['v1']], 'mocks_v1 was modified by the submission.'
    assert v2 == [tuple(row) for row in expected['v2']], 'mocks_v2 does not match the independent migration fixture.'
    with open(LOG_PATH, encoding='utf-8') as f:
        assert f.readlines() == expected['log'], 'The emulator output does not match the independent DSL fixture.'

def test_mocks_v2_table():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='mocks_v2'")
    assert c.fetchone() is not None, "Table 'mocks_v2' does not exist in the database."

    c.execute("PRAGMA table_info(mocks_v2)")
    columns = {row[1]: row[2].upper() for row in c.fetchall()}

    assert 'id' in columns, "Column 'id' is missing from 'mocks_v2'."
    assert 'endpoint' in columns, "Column 'endpoint' is missing from 'mocks_v2'."
    assert 'status_code' in columns, "Column 'status_code' is missing from 'mocks_v2'."
    assert 'response_body' in columns, "Column 'response_body' is missing from 'mocks_v2'."

    c.execute("SELECT id, endpoint, status_code, response_body FROM mocks_v2 ORDER BY id")
    actual_rows = c.fetchall()
    conn.close()

    expected_rows = get_expected_v2_data()
    assert expected_rows, "Could not compute expected data (mocks_v1 might be missing or corrupted)."

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in 'mocks_v2', got {len(actual_rows)}."
    assert actual_rows == expected_rows, "Data in 'mocks_v2' does not match the expected decoded values."

def test_results_log():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."
    assert os.path.exists(DSL_PATH), f"DSL file {DSL_PATH} is missing."

    expected_v2_data = get_expected_v2_data()
    db_map = {row[1]: (row[2], row[3]) for row in expected_v2_data}

    with open(DSL_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_log = []
    for i in range(0, len(lines), 2):
        if not lines[i].startswith("EXEC "):
            continue
        endpoint = lines[i].split(" ", 1)[1]
        assert_status = int(lines[i+1].split(" ")[1])

        if endpoint not in db_map:
            expected_log.append(f"[{endpoint}] ERROR: not found\n")
        else:
            db_status, db_body = db_map[endpoint]
            if db_status == assert_status:
                expected_log.append(f"[{endpoint}] PASS: {db_body}\n")
            else:
                expected_log.append(f"[{endpoint}] FAIL: expected {assert_status}, got {db_status}\n")

    with open(LOG_PATH, 'r') as f:
        actual_log = f.readlines()

    assert len(actual_log) == len(expected_log), f"Expected {len(expected_log)} lines in {LOG_PATH}, got {len(actual_log)}."

    for i, (actual, expected) in enumerate(zip(actual_log, expected_log)):
        assert actual == expected, f"Mismatch at line {i+1} in {LOG_PATH}.\nExpected: {expected.strip()}\nGot: {actual.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
