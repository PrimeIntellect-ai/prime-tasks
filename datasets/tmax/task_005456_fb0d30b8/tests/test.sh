#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import ssl
import subprocess
import time

import pytest

CERT_PATH = '/home/user/certs/server.crt'
KEY_PATH = '/home/user/certs/server.key'
SCRIPT_PATH = '/home/user/upload_server.sh'
TOKEN = 'SecOps-99A2-XYZ'


def run_ok(args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def listening_inodes():
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == '20FB' and fields[3] == '0A':
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def process_info(pid):
    try:
        with open(f'/proc/{pid}/status') as f:
            status = f.read()
        match = re.search(r'^PPid:\s+(\d+)$', status, re.MULTILINE)
        ppid = int(match.group(1)) if match else 0
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            cmd = f.read().replace(b'\0', b' ').decode(errors='ignore')
        return ppid, cmd
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return 0, ''


def stop_existing_server():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        deadline = time.time() + 2
        while time.time() < deadline:
            inodes = listening_inodes()
            if not inodes:
                return
            holders = set()
            for name in os.listdir('/proc'):
                if not name.isdigit():
                    continue
                pid = int(name)
                try:
                    for fd in os.listdir(f'/proc/{pid}/fd'):
                        try:
                            target = os.readlink(f'/proc/{pid}/fd/{fd}')
                        except OSError:
                            continue
                        if target.startswith('socket:[') and target[8:-1] in inodes:
                            holders.add(pid)
                            break
                except (FileNotFoundError, PermissionError):
                    pass
            victims = set(holders)
            for pid in list(holders):
                current = pid
                for _ in range(12):
                    ppid, cmd = process_info(current)
                    if SCRIPT_PATH in cmd:
                        victims.add(current)
                    if ppid <= 1:
                        break
                    current = ppid
            for pid in victims:
                if pid != os.getpid():
                    try:
                        os.kill(pid, sig)
                    except ProcessLookupError:
                        pass
            time.sleep(0.1)


def wait_for_tls(timeout=8):
    context = ssl._create_unverified_context()
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', 8443), timeout=0.5) as sock:
                with context.wrap_socket(sock, server_hostname='localhost'):
                    return
        except Exception as exc:
            last_error = exc
            time.sleep(0.15)
    pytest.fail(f'Script did not start a TLS listener on 127.0.0.1:8443: {last_error}')


@pytest.fixture(scope='session', autouse=True)
def run_submitted_script():
    assert os.path.isfile(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script at {SCRIPT_PATH} is not executable'
    stop_existing_server()
    proc = subprocess.Popen(
        [SCRIPT_PATH],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_tls()
    yield
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def test_certs_exist():
    assert os.path.isfile(CERT_PATH), f'Certificate not found at {CERT_PATH}'
    assert os.path.isfile(KEY_PATH), f'Private key not found at {KEY_PATH}'

    run_ok(['openssl', 'x509', '-in', CERT_PATH, '-noout', '-checkend', '0'])
    run_ok(['openssl', 'x509', '-in', CERT_PATH, '-noout', '-checkhost', 'localhost'])
    run_ok(['openssl', 'verify', '-CAfile', CERT_PATH, CERT_PATH])
    cert_pub = run_ok(['openssl', 'x509', '-in', CERT_PATH, '-pubkey', '-noout'])
    key_pub = run_ok(['openssl', 'pkey', '-in', KEY_PATH, '-pubout'])
    assert cert_pub == key_pub, 'server.crt and server.key do not form a matching key pair'


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script at {SCRIPT_PATH} is not executable'
    with open(SCRIPT_PATH, errors='ignore') as f:
        content = f.read()
    first_line = content.splitlines()[0] if content.splitlines() else ''
    assert 'bash' in first_line, 'upload_server.sh must be a Bash script'
    assert re.search(r'(^|[^A-Za-z0-9_])(socat|ncat)([^A-Za-z0-9_]|$)', content), \
        'upload_server.sh must use socat or ncat'
    assert not re.search(r'(^|[;&|[:space:]])(python[0-9.]*|ruby)([[:space:]]|$)', content), \
        'The server must not invoke Python or Ruby'


def test_listener_uses_submitted_certificate():
    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', 8443), timeout=5) as sock:
        with context.wrap_socket(sock, server_hostname='localhost') as ssock:
            peer_der = ssock.getpeercert(binary_form=True)
    with open(CERT_PATH) as f:
        pem = f.read()
    match = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', pem, re.S)
    assert match, 'server.crt does not contain a PEM certificate'
    file_der = ssl.PEM_cert_to_DER_cert(match.group(0))
    assert peer_der == file_der, 'TLS listener is not using /home/user/certs/server.crt'


def send_https_request(path, token=TOKEN):
    context = ssl._create_unverified_context()
    try:
        with socket.create_connection(('127.0.0.1', 8443), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname='localhost') as ssock:
                headers = [
                    f'POST {path} HTTP/1.1',
                    'Host: 127.0.0.1:8443',
                ]
                if token is not None:
                    headers.append(f'X-Auth-Token: {token}')
                headers.append('Connection: close')
                request = '\r\n'.join(headers) + '\r\n\r\n'
                ssock.sendall(request.encode())
                response = b''
                while True:
                    try:
                        chunk = ssock.recv(4096)
                    except socket.timeout:
                        break
                    if not chunk:
                        break
                    response += chunk
                return response
    except ConnectionRefusedError:
        pytest.fail('Connection refused. Is the server running on 127.0.0.1:8443?')
    except ssl.SSLError as exc:
        pytest.fail(f'SSL error occurred, TLS might not be configured correctly: {exc}')


def assert_response(response, status, body):
    assert b'\r\n\r\n' in response, f'Response lacks HTTP header terminator: {response!r}'
    head, actual_body = response.split(b'\r\n\r\n', 1)
    lines = head.split(b'\r\n')
    expected_line = f'HTTP/1.1 {status}'.encode()
    assert lines[0] == expected_line, f'Expected status line {expected_line!r}, got {lines[0]!r}'
    status_lines = re.findall(br'(?m)^HTTP/1\.[01] [0-9]{3}[^\r\n]*', response)
    assert status_lines == [expected_line], f'Response contains unexpected or multiple statuses: {response!r}'
    assert actual_body == body, f'Expected body {body!r}, got {actual_body!r}'


def test_valid_request():
    response = send_https_request('/upload?file=data.txt', TOKEN)
    assert b'200 OK' in response
    assert b'Success' in response
    assert_response(response, '200 OK', b'Success')


def test_invalid_token():
    response = send_https_request('/upload?file=data.txt', 'WrongToken')
    assert b'401 Unauthorized' in response
    assert_response(response, '401 Unauthorized', b'')


def test_path_traversal_attempt():
    response = send_https_request('/upload?file=../../../etc/shadow', TOKEN)
    assert b'403 Forbidden' in response
    assert_response(response, '403 Forbidden', b'')


def test_absolute_path_attempt():
    response = send_https_request('/upload?file=/etc/passwd', TOKEN)
    assert b'403 Forbidden' in response
    assert_response(response, '403 Forbidden', b'')


def test_randomized_authentication_and_safe_names():
    for _ in range(3):
        filename = f'{secrets.token_hex(8)}-{secrets.token_hex(4)}.dat'
        assert_response(send_https_request(f'/upload?file={filename}', TOKEN), '200 OK', b'Success')
        bad_token = secrets.token_urlsafe(18)
        assert bad_token != TOKEN
        assert_response(send_https_request(f'/upload?file={filename}', bad_token), '401 Unauthorized', b'')
    assert_response(send_https_request('/upload?file=safe.txt', None), '401 Unauthorized', b'')
    assert_response(send_https_request('/upload?file=safe.txt', TOKEN + 'x'), '401 Unauthorized', b'')
    assert_response(send_https_request('/upload?file=safe.txt', ' ' + TOKEN), '401 Unauthorized', b'')


def test_randomized_traversal_rejection():
    marker = secrets.token_hex(8)
    attempts = [
        f'/upload?file={marker}/../secret.txt',
        f'/upload?file=../{marker}',
        f'/upload?file=dir/../../{marker}',
        f'/upload?file=/{marker}/file.txt',
    ]
    for path in attempts:
        assert_response(send_https_request(path, TOKEN), '403 Forbidden', b'')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
