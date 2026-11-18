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
import subprocess
import uuid

import pytest
import requests

DB_FILE = '/home/user/db_breaches.txt'
VIDEO_FILE = '/home/user/video_breaches.txt'
GRAPH_SCRIPT = '/home/user/generate_graph.sh'
CYPHER_FILE = '/home/user/import.cypher'
AUDIT_SCRIPT = '/home/user/run_audit.sh'
BASE_URL = 'http://127.0.0.1:8080/check'
TOKEN = {'Authorization': 'Bearer AUDIT_SECURE_99'}


def get_db_breaches():
    conn = sqlite3.connect('/app/compliance.db')
    try:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT e.emp_id
            FROM employees e
            JOIN room_access r ON e.emp_id = r.emp_id
            WHERE e.clearance != 'TOP_SECRET' AND r.room = 'ServerRoom'
        ''')
        return {row[0] for row in cursor.fetchall()}
    finally:
        conn.close()


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def cypher_statement(emp_id):
    return f'MERGE (e:Employee {{emp_id: "{emp_id}"}}) MERGE (r:Room {{name: "ServerRoom"}}) MERGE (e)-[:UNAUTHORIZED_ACCESS]->(r);'


def restore_file(path, existed, data):
    if existed:
        with open(path, 'wb') as f:
            f.write(data)
    elif os.path.exists(path):
        os.remove(path)


def test_db_breaches_file():
    expected_db_breaches = get_db_breaches()
    assert os.path.exists(DB_FILE), f'File not found: {DB_FILE}'
    actual_db_breaches = set(read_nonempty_lines(DB_FILE))
    assert actual_db_breaches == expected_db_breaches, \
        f'Expected DB breaches {expected_db_breaches}, got {actual_db_breaches}'


def test_corrected_audit_script_is_executed_and_uses_the_database_join():
    assert os.path.isfile(AUDIT_SCRIPT), f'File not found or not a regular file: {AUDIT_SCRIPT}'

    suffix = uuid.uuid4().hex[:12].upper()
    breach_id = f'AUDIT_BREACH_{suffix}'
    no_access_id = f'AUDIT_NOACCESS_{suffix}'
    top_secret_id = f'AUDIT_TOP_{suffix}'

    output_existed = os.path.exists(DB_FILE)
    output_data = open(DB_FILE, 'rb').read() if output_existed else b''

    conn = sqlite3.connect('/app/compliance.db')
    try:
        conn.execute('INSERT INTO employees (emp_id, name, clearance) VALUES (?, ?, ?)',
                     (breach_id, 'Verifier Breach', 'SECRET'))
        conn.execute('INSERT INTO employees (emp_id, name, clearance) VALUES (?, ?, ?)',
                     (no_access_id, 'Verifier No Access', 'SECRET'))
        conn.execute('INSERT INTO employees (emp_id, name, clearance) VALUES (?, ?, ?)',
                     (top_secret_id, 'Verifier Top Secret', 'TOP_SECRET'))
        conn.execute('INSERT INTO room_access (emp_id, room, timestamp) VALUES (?, ?, ?)',
                     (breach_id, 'ServerRoom', '2023-10-01 11:00:00'))
        conn.execute('INSERT INTO room_access (emp_id, room, timestamp) VALUES (?, ?, ?)',
                     (top_secret_id, 'ServerRoom', '2023-10-01 11:01:00'))
        conn.commit()

        expected = get_db_breaches()
        with open(DB_FILE, 'w') as f:
            f.write('__VERIFIER_SENTINEL__\n')

        result = subprocess.run(
            ['bash', AUDIT_SCRIPT], text=True, capture_output=True, timeout=15
        )
        assert result.returncode == 0, \
            f'run_audit.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}'

        stdout_lines = {line.strip() for line in result.stdout.splitlines() if line.strip()}
        if stdout_lines:
            actual = stdout_lines
        else:
            assert os.path.exists(DB_FILE), 'run_audit.sh produced neither stdout nor db_breaches.txt'
            actual = set(read_nonempty_lines(DB_FILE))
            assert '__VERIFIER_SENTINEL__' not in actual, 'run_audit.sh did not regenerate db_breaches.txt'

        assert actual == expected, f'Executed audit script returned {actual}, expected {expected}'
        assert breach_id in actual
        assert no_access_id not in actual
        assert top_secret_id not in actual
    finally:
        conn.execute('DELETE FROM room_access WHERE emp_id IN (?, ?, ?)',
                     (breach_id, no_access_id, top_secret_id))
        conn.execute('DELETE FROM employees WHERE emp_id IN (?, ?, ?)',
                     (breach_id, no_access_id, top_secret_id))
        conn.commit()
        conn.close()
        restore_file(DB_FILE, output_existed, output_data)


def test_video_breaches_file():
    expected_video_breaches = {'EMP801', 'EMP805'}
    assert os.path.exists(VIDEO_FILE), f'File not found: {VIDEO_FILE}'
    actual_video_breaches = set(read_nonempty_lines(VIDEO_FILE))
    assert actual_video_breaches == expected_video_breaches, \
        f'Expected video breaches {expected_video_breaches}, got {actual_video_breaches}'


def test_import_cypher_file():
    all_breaches = get_db_breaches()
    all_breaches.update({'EMP801', 'EMP805'})

    assert os.path.exists(CYPHER_FILE), f'File not found: {CYPHER_FILE}'
    with open(CYPHER_FILE, 'r') as f:
        content = f.read()

    for emp_id in all_breaches:
        expected_stmt = cypher_statement(emp_id)
        assert expected_stmt in content, f'Missing or incorrect Cypher statement for {emp_id}'

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = {cypher_statement(emp_id) for emp_id in all_breaches}
    assert len(lines) == len(expected_lines), 'Cypher file contains duplicate or extra statements'
    assert set(lines) == expected_lines, 'Cypher file contains malformed or extra statements'


def test_generate_graph_script_reads_both_files_and_generates_exact_output():
    assert os.path.isfile(GRAPH_SCRIPT), f'File not found or not a regular file: {GRAPH_SCRIPT}'

    suffix = uuid.uuid4().hex[:12].upper()
    db_only = f'GRAPH_DB_{suffix}'
    video_only = f'GRAPH_VIDEO_{suffix}'
    shared = f'GRAPH_SHARED_{suffix}'
    expected_ids = {db_only, video_only, shared}

    backups = {}
    for path in (DB_FILE, VIDEO_FILE, CYPHER_FILE):
        existed = os.path.exists(path)
        backups[path] = (existed, open(path, 'rb').read() if existed else b'')

    try:
        with open(DB_FILE, 'w') as f:
            f.write(f'{db_only}\n{shared}\n{db_only}\n')
        with open(VIDEO_FILE, 'w') as f:
            f.write(f'{video_only}\n{shared}\n')

        result = subprocess.run(
            ['bash', GRAPH_SCRIPT], text=True, capture_output=True, timeout=15
        )
        assert result.returncode == 0, \
            f'generate_graph.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
        assert os.path.isfile(CYPHER_FILE), 'generate_graph.sh did not create import.cypher'

        lines = read_nonempty_lines(CYPHER_FILE)
        expected_lines = {cypher_statement(emp_id) for emp_id in expected_ids}
        assert len(lines) == len(expected_lines), 'Generated Cypher contains duplicates or extras'
        assert set(lines) == expected_lines, \
            f'Generated Cypher statements were {set(lines)}, expected {expected_lines}'
    finally:
        restore_file(DB_FILE, *backups[DB_FILE])
        restore_file(VIDEO_FILE, *backups[VIDEO_FILE])
        restore_file(CYPHER_FILE, *backups[CYPHER_FILE])


def checked_request(emp_id, headers=None):
    try:
        return requests.get(
            BASE_URL,
            params={'emp_id': emp_id},
            headers=headers or {},
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f'HTTP server is not reachable or failed: {e}')


def assert_status(emp_id, expected_body):
    resp = checked_request(emp_id, TOKEN)
    assert resp.status_code == 200, f'Expected HTTP 200 for {emp_id}, got {resp.status_code}'
    assert expected_body in resp.text, f'Expected {expected_body!r}, got {resp.text!r}'
    assert resp.content == expected_body.encode(), \
        f'Expected exact body {expected_body!r}, got {resp.content!r}'


def test_http_server():
    all_breaches = get_db_breaches()
    all_breaches.update({'EMP801', 'EMP805'})
    breach_id = next(iter(all_breaches)) if all_breaches else 'EMP042'

    resp = checked_request(breach_id, {'Authorization': 'Bearer WRONG_TOKEN'})
    assert resp.status_code == 401, f'Expected HTTP 401 for wrong token, got {resp.status_code}'

    resp = checked_request(breach_id)
    assert resp.status_code == 401, f'Expected HTTP 401 for missing token, got {resp.status_code}'

    for emp_id in sorted(all_breaches):
        assert_status(emp_id, 'STATUS: BREACH')

    for emp_id in ('EMP999', 'EMP001', f'CLEAR_{uuid.uuid4().hex.upper()}'):
        if emp_id not in all_breaches:
            assert_status(emp_id, 'STATUS: CLEAR')


def test_http_server_membership_tracks_either_breach_file():
    db_data = open(DB_FILE, 'rb').read()
    video_data = open(VIDEO_FILE, 'rb').read()
    suffix = uuid.uuid4().hex[:12].upper()
    db_dynamic = f'HTTP_DB_{suffix}'
    video_dynamic = f'HTTP_VIDEO_{suffix}'
    clear_dynamic = f'HTTP_CLEAR_{suffix}'

    try:
        with open(DB_FILE, 'ab') as f:
            if db_data and not db_data.endswith(b'\n'):
                f.write(b'\n')
            f.write((db_dynamic + '\n').encode())
        with open(VIDEO_FILE, 'ab') as f:
            if video_data and not video_data.endswith(b'\n'):
                f.write(b'\n')
            f.write((video_dynamic + '\n').encode())

        assert_status(db_dynamic, 'STATUS: BREACH')
        assert_status(video_dynamic, 'STATUS: BREACH')
        assert_status(clear_dynamic, 'STATUS: CLEAR')
    finally:
        with open(DB_FILE, 'wb') as f:
            f.write(db_data)
        with open(VIDEO_FILE, 'wb') as f:
            f.write(video_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
