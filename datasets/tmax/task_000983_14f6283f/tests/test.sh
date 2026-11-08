#!/bin/bash
mkdir -p /logs/verifier

fail_verifier() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

cat << 'PY_EOF' > /tmp/kill_listeners.py
import os
import signal
import time

PORTS = {6379, 8080, 9090}

def listener_inodes():
    found = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    port = int(local.rsplit(':', 1)[1], 16)
                    if state == '0A' and port in PORTS:
                        found.add(inode)
        except FileNotFoundError:
            pass
    return found

def pids_for(inodes):
    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) in (1, os.getpid()):
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids

pids = pids_for(listener_inodes())
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

time.sleep(1)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY_EOF

python3 /tmp/kill_listeners.py || fail_verifier
rm -f /home/user/log-pipeline/app.log
rm -f /home/user/log-pipeline/rust-parser/target/release/rust-parser

STARTED_AT=$(date +%s)
export STARTED_AT
if ! timeout 180 bash /home/user/log-pipeline/start_all.sh; then
    fail_verifier
fi

# Allow daemonized services a short readiness period.
python3 - << 'PY_EOF' || fail_verifier
import socket
import time

for port in (6379, 8080, 9090):
    deadline = time.time() + 30
    while True:
        s = socket.socket()
        s.settimeout(0.5)
        try:
            s.connect(('127.0.0.1', port))
            s.close()
            break
        except OSError:
            s.close()
            if time.time() >= deadline:
                raise SystemExit(f'port {port} did not become ready')
            time.sleep(0.2)
PY_EOF

# Remove persisted counters from earlier container activity without replacing Redis.
redis-cli -h 127.0.0.1 -p 6379 FLUSHALL >/dev/null 2>&1 || fail_verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import socket
import string
import subprocess
import threading
import time
import uuid

import pytest
import requests

ROOT = '/home/user/log-pipeline'
RUST_BINARY = ROOT + '/rust-parser/target/release/rust-parser'
URL = 'http://127.0.0.1:8080/ingest'


def random_word(prefix='x'):
    return prefix + uuid.uuid4().hex


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != '0A':
                        continue
                    if int(fields[1].rsplit(':', 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{name}/fd'):
                try:
                    target = os.readlink(f'/proc/{name}/fd/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as s:
            s.settimeout(0.3)
            if s.connect_ex(('127.0.0.1', port)) == 0:
                return
        time.sleep(0.1)
    pytest.fail(f'port {port} did not become ready')


def direct_rust(body):
    with socket.create_connection(('127.0.0.1', 9090), timeout=3) as sock:
        sock.sendall(body.encode())
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b'\n' in chunk:
                break
    return json.loads(b''.join(chunks).decode())


def test_start_script_and_log_exist():
    script_path = '/home/user/log-pipeline/start_all.sh'
    log_path = '/home/user/log-pipeline/app.log'

    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"
    assert os.path.isfile(log_path), f"{log_path} does not exist"


def test_release_binary_was_built_and_is_running():
    assert os.path.isfile(RUST_BINARY), 'start_all.sh did not build the release binary'
    assert open(RUST_BINARY, 'rb').read(4) == b'\x7fELF', 'release artifact is not an ELF executable'
    assert os.path.getmtime(RUST_BINARY) >= int(os.environ['STARTED_AT']) - 1

    pids = listener_pids(9090)
    assert pids, 'No process owns the Rust listening socket'
    executables = []
    for pid in pids:
        try:
            executables.append(os.path.realpath(f'/proc/{pid}/exe'))
        except OSError:
            pass
    assert os.path.realpath(RUST_BINARY) in executables, (
        f'port 9090 is not owned by the compiled Rust artifact: {executables}'
    )


def test_redis_process_is_listening():
    pids = listener_pids(6379)
    assert pids, 'Redis is not listening on 127.0.0.1:6379'
    names = []
    for pid in pids:
        try:
            names.append(os.path.basename(os.path.realpath(f'/proc/{pid}/exe')))
        except OSError:
            pass
    assert any('redis-server' in name for name in names), f'6379 is not owned by redis-server: {names}'


def test_rust_service_listening():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(('127.0.0.1', 9090))
    sock.close()
    assert result == 0, 'Rust TCP service is not listening on 127.0.0.1:9090'


def test_python_gateway_listening():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(('127.0.0.1', 8080))
    sock.close()
    assert result == 0, 'Python HTTP gateway is not listening on 127.0.0.1:8080'


def test_dynamic_rust_parsing():
    for _ in range(4):
        severity = ''.join(random.choice(string.ascii_uppercase) for _ in range(7))
        message = random_word('message-') + ' with spaces ' + str(random.randint(10000, 99999))
        assert direct_rust(f'[{severity}] {message}') == {
            'severity': severity,
            'message': message,
        }


def test_gateway_missing_auth():
    response = requests.post(URL, data='[INFO] Test message', timeout=4)
    assert response.status_code in [400, 401, 403], f'Expected auth failure status code, got {response.status_code}'


def test_gateway_rejects_malformed_authorization_formats():
    token = random_word('auth-')
    malformed = [
        f'Basic {token}',
        f'bearer {token}',
        f'Bearer  {token}',
        f'Bearer {token} extra',
        'Bearer',
        'Bearer ',
    ]
    for value in malformed:
        response = requests.post(URL, headers={'Authorization': value}, data='[INFO] auth', timeout=4)
        assert response.status_code in (400, 401, 403), (
            f'malformed Authorization header {value!r} was accepted with {response.status_code}'
        )


def test_gateway_valid_request():
    headers = {'Authorization': 'Bearer valid-token-1'}
    body = '[ERROR] Connection failed at 10:45'

    response = requests.post(URL, headers=headers, data=body, timeout=4)
    assert response.status_code == 200, f'Expected 200 OK, got {response.status_code}. Response: {response.text}'

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {response.text}')

    assert data.get('severity') == 'ERROR', f"Expected severity 'ERROR', got {data.get('severity')}"
    assert data.get('message') == 'Connection failed at 10:45', f"Expected message 'Connection failed at 10:45', got {data.get('message')}"


def test_gateway_dynamic_requests_and_per_token_isolation():
    severity = random_word('S').upper()
    message = random_word('dynamic-') + ' ' + uuid.uuid4().hex
    token_a = random_word('token-a-')
    token_b = random_word('token-b-')
    body = f'[{severity}] {message}'

    for _ in range(5):
        response = requests.post(URL, headers={'Authorization': f'Bearer {token_a}'}, data=body, timeout=4)
        assert response.status_code == 200
        assert response.json() == {'severity': severity, 'message': message}

    blocked = requests.post(URL, headers={'Authorization': f'Bearer {token_a}'}, data=body, timeout=4)
    assert blocked.status_code == 429, 'The sixth request for one token must be rejected'

    independent = requests.post(URL, headers={'Authorization': f'Bearer {token_b}'}, data=body, timeout=4)
    assert independent.status_code == 200, 'A different token must have an independent limit'
    assert independent.json() == {'severity': severity, 'message': message}


def test_gateway_uses_redis_for_rate_tracking():
    monitor = socket.create_connection(('127.0.0.1', 6379), timeout=3)
    monitor.settimeout(2)
    monitor.sendall(b'MONITOR\r\n')
    acknowledgement = b''
    while b'\r\n' not in acknowledgement:
        acknowledgement += monitor.recv(1024)
    assert acknowledgement.startswith(b'+OK')

    token = random_word('redis-observed-')
    response = requests.post(
        URL,
        headers={'Authorization': f'Bearer {token}'},
        data='[INFO] redis observation ' + uuid.uuid4().hex,
        timeout=4,
    )
    assert response.status_code == 200

    observed = b''
    deadline = time.time() + 2
    while time.time() < deadline:
        try:
            observed += monitor.recv(8192)
        except socket.timeout:
            break
    monitor.close()
    text = observed.decode('utf-8', 'replace').lower()
    mutating = re.search(r'"(incr|incrby|hincrby|set|setex|psetex|zadd|eval|evalsha)"', text)
    assert mutating, f'Gateway request produced no Redis rate-counter mutation. MONITOR output: {text!r}'


def test_gateway_rate_limiting():
    headers = {'Authorization': 'Bearer rate-limit-token-1'}
    body = '[WARN] Rate limit test'

    time.sleep(1.1)

    success_count = 0
    too_many_count = 0

    for _ in range(10):
        response = requests.post(URL, headers=headers, data=body, timeout=4)
        if response.status_code == 200:
            success_count += 1
        elif response.status_code == 429:
            too_many_count += 1

    assert success_count <= 5, f'Rate limit failed: {success_count} requests succeeded, expected at most 5'
    assert too_many_count >= 5, f'Rate limit failed: {too_many_count} requests returned 429, expected at least 5'

    time.sleep(1.1)

    response = requests.post(URL, headers=headers, data=body, timeout=4)
    assert response.status_code == 200, f'Expected 200 OK after waiting, got {response.status_code}'


def test_gateway_actually_forwards_plaintext_to_tcp_backend():
    rust_pids = listener_pids(9090)
    assert rust_pids
    for pid in rust_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while listener_pids(9090) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(9090):
        os.kill(pid, signal.SIGKILL)
    time.sleep(0.2)

    captured = []
    ready = threading.Event()
    marker = random_word('backend-marker-')
    backend_response = {'severity': marker, 'message': random_word('backend-message-')}

    def backend():
        with socket.socket() as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(('127.0.0.1', 9090))
            server.listen(1)
            ready.set()
            conn, _ = server.accept()
            with conn:
                conn.settimeout(3)
                captured.append(conn.recv(4096))
                conn.sendall((json.dumps(backend_response) + '\n').encode())

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(3)

    body = '[NOTICE] ' + random_word('forward-me-')
    token = random_word('forward-token-')
    response = requests.post(URL, headers={'Authorization': f'Bearer {token}'}, data=body, timeout=5)
    thread.join(3)

    try:
        assert response.status_code == 200, response.text
        assert response.json() == backend_response, 'Gateway did not return the TCP backend response'
        assert captured, 'Gateway never connected to the replacement TCP backend'
        assert captured[0].decode().rstrip('\r\n') == body, 'Gateway did not forward the plaintext request body'
    finally:
        log = open(ROOT + '/app.log', 'ab', buffering=0)
        subprocess.Popen(
            [RUST_BINARY],
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            close_fds=True,
        )
        wait_for_port(9090, timeout=10)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
