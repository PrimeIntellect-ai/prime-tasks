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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import signal
import socket
import sqlite3
import subprocess
import threading
import time
from pathlib import Path

import pytest
import requests


def expected_pin():
    log = Path('/app/logs/system.log').read_text()
    hashes = re.findall(r'\b[a-fA-F0-9]{64}\b', log)
    assert hashes, 'No SHA-256 hash found in system.log'
    for candidate in range(10000):
        pin = f'{candidate:04d}'
        digest = hashlib.sha256(pin.encode()).hexdigest()
        if any(digest.lower() == value.lower() for value in hashes):
            return pin
    pytest.fail('The logged SHA-256 hash does not correspond to a 4-digit PIN')


def listener_pid(port):
    wanted = f'{port:04X}'
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if local.rsplit(':', 1)[1].upper() == wanted and state == '0A':
                inodes.add(fields[9])
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    return int(proc.name)
        except OSError:
            continue
    return None


def wait_for_listener(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = listener_pid(port)
        if pid is not None:
            return pid
        time.sleep(0.05)
    return None


def assert_release_listener(port, project, binary):
    expected = Path(f'/app/{project}/target/release/{binary}').resolve()
    assert expected.is_file(), f'Missing release binary: {expected}'
    assert os.access(expected, os.X_OK), f'Release binary is not executable: {expected}'

    inputs = [Path(f'/app/{project}/Cargo.toml')]
    inputs.extend(Path(f'/app/{project}/src').rglob('*.rs'))
    assert expected.stat().st_mtime_ns >= max(path.stat().st_mtime_ns for path in inputs), \
        f'{expected} is older than its Rust source; run cargo build --release'

    pid = listener_pid(port)
    assert pid is not None, f'Nothing is listening on 127.0.0.1:{port}'
    actual = Path(os.readlink(f'/proc/{pid}/exe')).resolve()
    assert actual == expected, f'Port {port} is served by {actual}, not {expected}'
    return pid


def raw_http(target):
    with socket.create_connection(('127.0.0.1', 8000), timeout=3) as sock:
        sock.sendall(f'GET {target} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n'.encode())
        sock.settimeout(3)
        chunks = []
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
    response = b''.join(chunks)
    head, _, body = response.partition(b'\r\n\r\n')
    first = head.split(b'\r\n', 1)[0]
    match = re.match(rb'HTTP/\d(?:\.\d)?\s+(\d+)', first)
    assert match, f'Invalid HTTP response: {response!r}'
    return int(match.group(1)), body.decode(errors='replace')


def test_cracked_pin_file():
    pin_path = Path('/app/cracked_pin.txt')
    assert pin_path.exists(), f'Cracked PIN file not found at {pin_path}'
    assert pin_path.is_file(), f'{pin_path} is not a file'
    assert pin_path.read_text().strip() == expected_pin()


def test_parameterized_rust_source():
    source_path = Path('/app/evidence_api/src/main.rs')
    assert source_path.is_file(), 'evidence_api Rust source is missing'
    source = source_path.read_text()

    assert re.search(r'SELECT\s+.+?FROM\s+evidence\s+WHERE\s+id\s*=\s*(?:\?\d*|:[A-Za-z_]\w*)',
                     source, re.IGNORECASE | re.DOTALL), \
        'The evidence query must contain a SQLite bind placeholder'
    assert (re.search(r'\.(?:query|query_row|execute)\s*\(\s*(?:rusqlite::)?params!\s*\[', source, re.DOTALL)
            or re.search(r'\.(?:query|query_row|execute)\s*\(\s*&?\s*\[', source, re.DOTALL)
            or 'raw_bind_parameter' in source), \
        'The request parameter is not bound to the SQLite statement'
    assert not re.search(r'format!\s*\(\s*(?:r#*)?["#][^\n]*SELECT', source, re.IGNORECASE), \
        'SQL is still being constructed with format!'

    assert re.search(r'ADMIN_TOKEN', source), 'evidence_api does not read/use ADMIN_TOKEN'
    assert re.search(r'\bconnect\b', source) and '9000' in source, \
        'evidence_api source does not connect to audit_logger on port 9000'


def test_release_services_and_environment():
    audit_pid = assert_release_listener(9000, 'audit_logger', 'audit_logger')
    api_pid = assert_release_listener(8000, 'evidence_api', 'evidence_api')
    assert audit_pid != api_pid

    environ = Path(f'/proc/{api_pid}/environ').read_bytes().split(b'\0')
    values = [item.split(b'=', 1)[1].decode(errors='replace')
              for item in environ if item.startswith(b'ADMIN_TOKEN=')]
    assert values == [expected_pin()], 'Running evidence_api has the wrong or missing ADMIN_TOKEN'


def test_normal_and_parameterized_query_behavior():
    resp = requests.get('http://127.0.0.1:8000/record?id=1', timeout=3)
    assert resp.status_code == 200, f'Expected 200 OK for valid ID, got {resp.status_code}'
    assert resp.text.strip(), 'Expected non-empty response for valid ID'

    # Preserve the original encoded-payload checks.
    for payload in ["1' OR '1'='1", "1' OR 1=1--"]:
        injected = requests.get('http://127.0.0.1:8000/record', params={'id': payload}, timeout=3)
        if injected.status_code == 200:
            assert injected.text != resp.text, f'SQL injection vulnerability remains for {payload}'
            if injected.text.strip().startswith('['):
                assert injected.text.strip() == '[]'
            else:
                assert len(injected.text.strip()) < len(resp.text.strip())

    # Add a verifier-generated row so a fixed-response listener cannot pass.
    random_id = secrets.randbelow(800_000_000) + 100_000_000
    marker = '{"evidence":"verify-' + secrets.token_hex(16) + '"}'
    db = sqlite3.connect('/app/evidence.db')
    try:
        db.execute('INSERT INTO evidence(id, data) VALUES (?, ?)', (random_id, marker))
        db.commit()
        dynamic = requests.get('http://127.0.0.1:8000/record', params={'id': str(random_id)}, timeout=3)
        assert dynamic.status_code == 200
        assert marker in dynamic.text, 'evidence_api did not query the verifier-generated record'

        # Literal, non-URL-encoded payload: the original concatenated SQL executes this.
        payload = f"{random_id}'/**/OR/**/'1'='1"
        status, body = raw_http('/record?id=' + payload)
        assert marker not in body, 'Raw SQL injection returned the generated evidence record'
        assert body.strip() != dynamic.text.strip(), 'Raw SQL injection behaved like a valid lookup'
    finally:
        db.execute('DELETE FROM evidence WHERE id = ?', (random_id,))
        db.commit()
        db.close()


def test_evidence_api_really_contacts_audit_logger():
    logger_pid = assert_release_listener(9000, 'audit_logger', 'audit_logger')
    replacement = None
    probe = None
    received = []
    try:
        os.kill(logger_pid, signal.SIGTERM)
        deadline = time.time() + 3
        while Path(f'/proc/{logger_pid}').exists() and time.time() < deadline:
            time.sleep(0.05)
        if Path(f'/proc/{logger_pid}').exists():
            os.kill(logger_pid, signal.SIGKILL)
            time.sleep(0.1)

        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(('127.0.0.1', 9000))
        probe.listen(8)
        probe.settimeout(0.5)

        for _ in range(3):
            response = requests.get('http://127.0.0.1:8000/record?id=1', timeout=3)
            assert response.status_code == 200

        deadline = time.time() + 3
        while time.time() < deadline and not received:
            try:
                conn, _ = probe.accept()
            except socket.timeout:
                continue
            with conn:
                conn.settimeout(1)
                try:
                    data = conn.recv(4096)
                except socket.timeout:
                    data = b''
                if data:
                    received.append(data)
        assert received, 'evidence_api made requests without sending an access log to port 9000'
    finally:
        if probe is not None:
            probe.close()
        replacement = subprocess.Popen(
            ['/app/audit_logger/target/release/audit_logger'],
            cwd='/app/audit_logger', stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        assert wait_for_listener(9000, 5) is not None, 'Failed to restore audit_logger after verification'
        assert_release_listener(9000, 'audit_logger', 'audit_logger')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
