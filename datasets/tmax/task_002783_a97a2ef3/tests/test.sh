#!/bin/bash
mkdir -p /logs/verifier
status=0
oracle_backup="/tmp/legacy_auth_gen.verifier.$$"

stop_listener() {
python3 - <<'PY'
import os, signal, time

def listener_inodes():
    result = set()
    try:
        with open('/proc/net/tcp') as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].upper() == '0100007F:2382' and fields[3] == '0A':
                    result.add(fields[9])
    except OSError:
        pass
    return result

def pids_for(inodes):
    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except OSError:
            continue
    return result

for sig in (signal.SIGTERM, signal.SIGKILL):
    inodes = listener_inodes()
    if not inodes:
        break
    for pid in pids_for(inodes):
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
PY
}

wait_for_service() {
python3 - <<'PY'
import socket, sys, time
for _ in range(50):
    try:
        with socket.create_connection(('127.0.0.1', 9090), timeout=0.2):
            sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit(1)
PY
}

cleanup() {
    stop_listener >/dev/null 2>&1 || true
    if [ -e "$oracle_backup" ]; then
        mv "$oracle_backup" /app/legacy_auth_gen
    fi
    rm -f /tmp/auth_service_rebuilt /tmp/auth_service_submitted.log /tmp/auth_service_asan.log
}
trap cleanup EXIT

cat <<'PYTEST' > /tmp/test_original_state.py
import hashlib
import os
import socket
import sqlite3
import pytest


def transform(x: int) -> int:
    x &= 0xFFFFFFFF
    return (((x * 1664525) + 1013904223) & 0xFFFFFFFF) ^ (x >> 16)


def send_tcp_request(host: str, port: int, message: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        s.connect((host, port))
        s.sendall(message.encode('utf-8'))
        response = b''
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            response += chunk
            if b'\n' in response:
                break
        return response.decode('utf-8')


def test_required_c_artifacts_exist():
    source = '/home/user/auth_service.c'
    binary = '/home/user/auth_service'
    assert os.path.isfile(source), f'Missing C source at {source}'
    assert not os.path.islink(source), f'{source} must be a regular source file'
    assert os.path.isfile(binary), f'Missing compiled service at {binary}'
    assert os.access(binary, os.X_OK), f'{binary} is not executable'
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{binary} is not an ELF executable'
    with open(binary, 'rb') as f:
        submitted_hash = hashlib.sha256(f.read()).digest()
    with open('/app/legacy_auth_gen', 'rb') as f:
        legacy_hash = hashlib.sha256(f.read()).digest()
    assert submitted_hash != legacy_hash, 'Replacement binary is identical to the legacy executable'


def test_service_valid_requests():
    host = '127.0.0.1'
    port = 9090
    test_cases = [10, 9999, 123456, 0, 4294967295]
    for val in test_cases:
        expected_output = transform(val)
        message = f'GENERATE {val} AUTH ci_cd_pipe_88\n'
        try:
            response = send_tcp_request(host, port, message)
        except Exception as e:
            pytest.fail(f'Failed to connect or receive from service for valid request: {e}')
        assert response == f'SUCCESS {expected_output}\n', f'Service returned incorrect response for input {val}: {response!r}'


def test_service_invalid_requests():
    host = '127.0.0.1'
    port = 9090
    invalid_messages = [
        'GENERATE 10 AUTH wrong_secret\n',
        'GENERATE 10 AUTH\n',
        'GENERATE AUTH ci_cd_pipe_88\n',
        'INVALID FORMAT\n',
        'GENERATE 10 AUTH ci_cd_pipe_88 extra\n'
    ]
    for msg in invalid_messages:
        try:
            response = send_tcp_request(host, port, msg)
        except Exception as e:
            pytest.fail(f'Failed to connect or receive from service for invalid request: {e}')
        assert response == 'ERROR\n', f'Service did not return ERROR\\n for invalid request {msg!r}. Got: {response!r}'


def test_metrics_v2_db_migration():
    db_path = '/home/user/metrics_v2.db'
    assert os.path.exists(db_path), f'Missing migrated database at {db_path}'
    assert os.path.isfile(db_path), f'{db_path} is not a file'
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='auth_logs';")
    assert cursor.fetchone() is not None, "Table 'auth_logs' does not exist in migrated database"
    cursor.execute('PRAGMA table_info(auth_logs);')
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    assert 'log_id' in columns, "Column 'log_id' missing from auth_logs table"
    assert 'requested_val' in columns, "Column 'requested_val' missing from auth_logs table"
    assert 'generated_val' in columns, "Column 'generated_val' missing from auth_logs table"
    assert 'migration_date' in columns, "Column 'migration_date' missing from auth_logs table"
    cursor.execute('SELECT requested_val, generated_val, migration_date FROM auth_logs ORDER BY requested_val;')
    rows = cursor.fetchall()
    expected_inputs = [10, 9999, 123456]
    expected_data = sorted([(val, transform(val), '2023-10-01') for val in expected_inputs], key=lambda x: x[0])
    assert len(rows) == len(expected_data), f'Expected {len(expected_data)} rows in auth_logs table, found {len(rows)}'
    for expected, actual in zip(expected_data, rows):
        assert expected == actual, f'Row mismatch: expected {expected}, got {actual}'
    conn.close()

    legacy = sqlite3.connect('/app/metrics_legacy.db')
    legacy_rows = legacy.execute('SELECT id, input_val FROM logs ORDER BY id').fetchall()
    legacy.close()
    migrated = sqlite3.connect(db_path)
    actual = migrated.execute('SELECT log_id, requested_val, generated_val, migration_date FROM auth_logs ORDER BY log_id').fetchall()
    migrated.close()
    expected = [(row_id, val, transform(val), '2023-10-01') for row_id, val in legacy_rows]
    assert actual == expected, f'Migrated rows do not exactly correspond to all legacy rows: expected {expected}, got {actual}'
PYTEST

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short 2>&1; then
    status=1
fi

cat <<'PYTEST' > /tmp/test_random_service.py
import secrets
import socket


def transform(x: int) -> int:
    x &= 0xFFFFFFFF
    return (((x * 1664525) + 1013904223) & 0xFFFFFFFF) ^ (x >> 16)


def request(message: str) -> str:
    with socket.create_connection(('127.0.0.1', 9090), timeout=2.0) as s:
        s.settimeout(2.0)
        s.sendall(message.encode())
        data = b''
        while b'\n' not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data.decode()


def test_unpredictable_valid_inputs():
    fixed_edges = [1, 2, 65535, 65536, 2147483647, 2147483648, 4294967294]
    random_values = [secrets.randbits(32) for _ in range(48)]
    for value in fixed_edges + random_values:
        assert request(f'GENERATE {value} AUTH ci_cd_pipe_88\n') == f'SUCCESS {transform(value)}\n'


def test_unpredictable_bad_secrets_and_formats():
    for _ in range(16):
        value = secrets.randbits(32)
        bad_secret = secrets.token_hex(12)
        assert bad_secret != 'ci_cd_pipe_88'
        assert request(f'GENERATE {value} AUTH {bad_secret}\n') == 'ERROR\n'
    malformed = [
        'GENERATE 7 AUTH ci_cd_pipe_88 trailing\n',
        'GENERATE\t7 AUTH ci_cd_pipe_88\n',
        ' GENERATE 7 AUTH ci_cd_pipe_88\n',
        'GENERATE 7 AUTH ci_cd_pipe_88',
        'GENERATE 7 AUTH ci_cd_pipe_88\nextra\n',
    ]
    for message in malformed:
        assert request(message) == 'ERROR\n'
PYTEST

if [ "$status" -eq 0 ]; then
    stop_listener
    if [ -e /app/legacy_auth_gen ]; then
        mv /app/legacy_auth_gen "$oracle_backup"
    else
        status=1
    fi
fi

# Execute the exact submitted binary with the legacy oracle unavailable.
if [ "$status" -eq 0 ]; then
    /home/user/auth_service >/tmp/auth_service_submitted.log 2>&1 &
    if ! wait_for_service; then
        status=1
    elif ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_random_service.py -x --tb=short 2>&1; then
        status=1
    fi
    stop_listener
fi

# Rebuild the submitted C source with runtime memory/undefined-behavior sanitizers,
# then execute that rebuilt artifact on another independently generated test set.
if [ "$status" -eq 0 ]; then
    if ! gcc -std=c11 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined /home/user/auth_service.c -o /tmp/auth_service_rebuilt -lsqlite3 -pthread >/tmp/auth_service_compile.log 2>&1; then
        cat /tmp/auth_service_compile.log
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1 /tmp/auth_service_rebuilt >/tmp/auth_service_asan.log 2>&1 &
    if ! wait_for_service; then
        cat /tmp/auth_service_asan.log
        status=1
    elif ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_random_service.py -x --tb=short 2>&1; then
        status=1
    fi
    stop_listener
    sleep 0.2
    if grep -E 'ERROR: (AddressSanitizer|LeakSanitizer)|runtime error:|AddressSanitizer:DEADLYSIGNAL' /tmp/auth_service_asan.log >/dev/null 2>&1; then
        cat /tmp/auth_service_asan.log
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
