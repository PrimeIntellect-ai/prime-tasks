#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import socket
import sqlite3
import subprocess
import time
import urllib.request

DB = '/app/audit.db'
SRC = '/home/user/audit_server.c'
BIN = '/tmp/audit_server_submission'
BASE = 'http://127.0.0.1:8080'
server = None
created_emp_ids = []
created_log_ids = []


def listening_pids(port):
    inodes = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and int(fields[1].split(':')[1], 16) == port and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass
    pids = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(entry))
        except OSError:
            pass
    return pids


def stop_port_8080():
    for pid in listening_pids(8080):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(8080):
        time.sleep(0.05)
    for pid in listening_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def get_json(path):
    req = urllib.request.Request(BASE + path, method='GET')
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f'Expected HTTP 200, got {response.status}'
        content_type = response.headers.get('Content-Type', '').lower()
        assert 'application/json' in content_type, f'Expected application/json, got {content_type!r}'
        body = response.read().decode('utf-8')
    try:
        return json.loads(body)
    except ValueError as exc:
        raise AssertionError(f'Response is not valid JSON: {body}') from exc


def signature(emp_id, res_id, timestamp):
    result = subprocess.run(
        ['/app/verify_sig', str(emp_id), str(res_id), str(timestamp)],
        check=True, capture_output=True, text=True, timeout=3
    )
    return int(result.stdout.strip())


def assert_payload(data, manager_id, page, limit, expected_rows):
    assert data.get('manager_id') == manager_id, data
    assert data.get('page') == page, data
    assert data.get('limit') == limit, data
    assert 'tampered_logs' in data, "Response missing 'tampered_logs' key"
    actual = data['tampered_logs']
    assert isinstance(actual, list), 'tampered_logs must be an array'
    assert actual == expected_rows, f'Expected {expected_rows}, got {actual}'


def row(log_id, emp_id, res_id, timestamp, db_sig):
    return {
        'log_id': log_id,
        'emp_id': emp_id,
        'res_id': res_id,
        'timestamp': timestamp,
        'db_sig': db_sig,
        'expected_sig': signature(emp_id, res_id, timestamp),
    }


def test_source_and_indexes():
    assert os.path.isfile(SRC), f'Missing C source at {SRC}'
    assert not os.path.islink(SRC), 'C source must be a regular file'
    source = open(SRC, 'rb').read()
    assert source and b'main' in source and b'#include' in source, 'audit_server.c does not look like C source'

    conn = sqlite3.connect(DB)
    indexes = conn.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index'").fetchall()
    index_tables = [table for _, table in indexes]
    # Preserve the original table-level assertions.
    assert 'Employees' in index_tables, 'No index created on Employees'
    assert 'AccessLogs' in index_tables, 'No index created on AccessLogs'

    def index_columns(table):
        result = []
        for item in conn.execute(f'PRAGMA index_list({table})'):
            name = item[1]
            cols = [r[2] for r in conn.execute(f'PRAGMA index_info("{name}")') if r[2] is not None]
            if cols:
                result.append(cols)
        return result

    employee_indexes = index_columns('Employees')
    access_indexes = index_columns('AccessLogs')
    assert any(cols[0] == 'manager_id' for cols in employee_indexes), \
        f'Employees needs an index beginning with manager_id; found {employee_indexes}'
    assert any(cols[0] == 'emp_id' for cols in access_indexes), \
        f'AccessLogs needs an index beginning with emp_id; found {access_indexes}'
    assert any('timestamp' in cols for cols in access_indexes), \
        f'AccessLogs needs a timestamp index; found {access_indexes}'
    conn.close()


def compile_and_start():
    global server
    stop_port_8080()
    subprocess.run(
        ['gcc', '-O2', '-Wall', '-Wextra', SRC, '-o', BIN,
         '-lsqlite3', '-lmicrohttpd', '-pthread'],
        check=True, capture_output=True, text=True, timeout=30
    )
    server = subprocess.Popen([BIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              start_new_session=True)
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if server.poll() is not None:
            raise AssertionError(f'Compiled server exited with status {server.returncode}')
        try:
            get_json('/tampered?manager_id=999999999&page=1&limit=1')
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f'Compiled server did not become ready: {last_error}')


def install_unpredictable_fixture():
    seed = secrets.randbelow(100000000) + 500000000
    root, child, grandchild, sibling, outsider = [seed + x for x in range(5)]
    base_log = seed * 10
    base_ts = 1700000000 + secrets.randbelow(10000000)
    employees = [
        (root, 'Verifier root', None),
        (child, 'Verifier child', root),
        (grandchild, 'Verifier grandchild', child),
        (sibling, 'Verifier sibling', root),
        (outsider, 'Verifier outsider', None),
    ]
    specs = [
        (base_log + 1, grandchild, 701, base_ts + 900, True),
        (base_log + 2, child, 702, base_ts + 1000, False),
        (base_log + 20, root, 703, base_ts + 800, True),
        (base_log + 10, sibling, 704, base_ts + 800, True),
        (base_log + 30, child, 705, base_ts + 700, True),
        (base_log + 40, outsider, 706, base_ts + 2000, True),
        (base_log + 50, grandchild, 707, base_ts + 1100, False),
    ]
    logs = []
    expected = {}
    for log_id, emp_id, res_id, ts, tampered in specs:
        sig = signature(emp_id, res_id, ts)
        db_sig = sig + 1234567 if tampered else sig
        logs.append((log_id, emp_id, res_id, ts, db_sig))
        expected[log_id] = row(log_id, emp_id, res_id, ts, db_sig)

    conn = sqlite3.connect(DB, timeout=5)
    conn.executemany('INSERT INTO Employees(emp_id,name,manager_id) VALUES (?,?,?)', employees)
    conn.executemany('INSERT INTO AccessLogs(log_id,emp_id,res_id,timestamp,hash_sig) VALUES (?,?,?,?,?)', logs)
    conn.commit()
    conn.close()
    created_emp_ids.extend(x[0] for x in employees)
    created_log_ids.extend(x[0] for x in logs)
    return root, child, outsider, expected, base_log


def test_original_cases():
    data = get_json('/tampered?manager_id=2&page=1&limit=10')
    assert [x.get('log_id') for x in data['tampered_logs']] == [104, 102, 106]

    data = get_json('/tampered?manager_id=1&page=2&limit=2')
    logs = data['tampered_logs']
    assert [x.get('log_id') for x in logs] == [102, 106]
    expected_keys = {'log_id', 'emp_id', 'res_id', 'timestamp', 'db_sig', 'expected_sig'}
    assert expected_keys.issubset(logs[0].keys())
    assert logs[0]['log_id'] == 102
    assert logs[0]['db_sig'] == 99999
    assert logs[0]['expected_sig'] == signature(2, 11, 1600000200)

    data = get_json('/tampered?manager_id=1&page=10&limit=10')
    assert data['tampered_logs'] == []

    # This additionally checks the binary's exceptional signature case is honored:
    # valid log 101 must not be reported as tampered.
    data = get_json('/tampered?manager_id=1&page=1&limit=20')
    assert [x.get('log_id') for x in data['tampered_logs']] == [105, 104, 102, 106]


def test_dynamic_database_behavior(fixture):
    root, child, outsider, expected, base = fixture
    root_order = [base + 1, base + 10, base + 20, base + 30]
    child_order = [base + 1, base + 30]

    assert_payload(get_json(f'/tampered?manager_id={root}&page=1&limit=20'),
                   root, 1, 20, [expected[i] for i in root_order])
    assert_payload(get_json(f'/tampered?manager_id={root}&page=2&limit=2'),
                   root, 2, 2, [expected[i] for i in root_order[2:4]])
    assert_payload(get_json(f'/tampered?manager_id={child}&page=1&limit=20'),
                   child, 1, 20, [expected[i] for i in child_order])
    assert_payload(get_json(f'/tampered?manager_id={outsider}&page=1&limit=20'),
                   outsider, 1, 20, [expected[base + 40]])
    assert_payload(get_json(f'/tampered?manager_id={root}&page=99&limit=3'),
                   root, 99, 3, [])


def cleanup():
    if created_log_ids or created_emp_ids:
        try:
            conn = sqlite3.connect(DB, timeout=2)
            if created_log_ids:
                conn.executemany('DELETE FROM AccessLogs WHERE log_id=?', [(x,) for x in created_log_ids])
            if created_emp_ids:
                conn.executemany('DELETE FROM Employees WHERE emp_id=?', [(x,) for x in created_emp_ids])
            conn.commit()
            conn.close()
        except Exception:
            pass
    if server is not None and server.poll() is None:
        try:
            os.killpg(server.pid, signal.SIGTERM)
            server.wait(timeout=2)
        except Exception:
            try:
                os.killpg(server.pid, signal.SIGKILL)
            except Exception:
                pass
    stop_port_8080()


def main():
    try:
        test_source_and_indexes()
        compile_and_start()
        # Insert after startup so fixed responses and startup snapshots cannot pass.
        fixture = install_unpredictable_fixture()
        test_original_cases()
        test_dynamic_database_behavior(fixture)
    finally:
        cleanup()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
