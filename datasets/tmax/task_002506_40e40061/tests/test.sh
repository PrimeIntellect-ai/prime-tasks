#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import signal
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

DEPLOY = '/home/user/deploy.sh'
SOURCE = '/home/user/src/main.rs'
BINARY = '/home/user/api_server'
CONFIG = '/home/user/service_config.txt'
LOG = '/home/user/deploy_success.log'


def listener_pids():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address, state, inode = fields[1], fields[3], fields[9]
                    if state == '0A' and int(address.rsplit(':', 1)[1], 16) == 8443:
                        inodes.add(inode)
        except FileNotFoundError:
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
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
        except OSError:
            continue
    return pids


def stop_port_8443():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), 'Could not clear the existing listener on port 8443.'


def get_expected_token():
    """Helper to extract the expected token from service_config.txt."""
    assert os.path.exists(CONFIG), f"Configuration file {CONFIG} does not exist."
    with open(CONFIG, 'r') as f:
        content = f.read().strip()
    for line in content.splitlines():
        if line.startswith('TOKEN='):
            return line.split('=', 1)[1].strip()
    pytest.fail(f"Could not find 'TOKEN=' in {CONFIG}.")


def raw_status_request():
    with socket.create_connection(('127.0.0.1', 8443), timeout=2) as sock:
        sock.settimeout(2)
        sock.sendall(b'GET /status HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n')
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    response = b''.join(chunks)
    assert b'\r\n\r\n' in response, 'Response is not a valid HTTP response.'
    headers, body = response.split(b'\r\n\r\n', 1)
    assert headers.split(b'\r\n', 1)[0] == b'HTTP/1.1 200 OK'
    return body


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            digest.update(chunk)
    return digest.digest()


def test_deploy_script_exists_and_executable():
    """Verify /home/user/deploy.sh exists and is executable."""
    assert os.path.exists(DEPLOY), f"Deployment script {DEPLOY} does not exist."
    assert os.path.isfile(DEPLOY), f"{DEPLOY} is not a file."
    st = os.stat(DEPLOY)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deployment script {DEPLOY} is not executable."


def test_execute_complete_deployment_workflow():
    assert os.path.isfile(SOURCE), f'{SOURCE} does not exist.'
    with open(DEPLOY, errors='replace') as f:
        script = f.read()
    with open(SOURCE, errors='replace') as f:
        source = f.read()

    assert re.search(r'\bexpect\b', script), 'deploy.sh must use expect.'
    for required in ('/home/user/legacy_config_gen.sh', 'production', 'api_worker'):
        assert required in script, f'deploy.sh is missing required expect workflow value: {required}'
    assert re.search(r'rustc\s+/home/user/src/main\.rs\s+-o\s+/home/user/api_server(?:\s|$)', script), \
        'deploy.sh must compile main.rs with the required rustc command.'
    assert re.search(r'(?m)^\s*(?:nohup\s+)?/home/user/api_server[^\n]*&\s*$', script), \
        'deploy.sh must start /home/user/api_server in the background.'
    assert re.search(r'(?m)^\s*sleep\s+2(?:\.0*)?\s*$', script), 'deploy.sh must wait 2 seconds.'
    assert 'http://127.0.0.1:8443/status' in script and re.search(r'\bcurl\b', script), \
        'deploy.sh must perform the required curl health check.'

    assert 'TcpListener' in source and 'std::net' in source, 'main.rs must use std::net::TcpListener.'
    assert 'std::io' in source and '.accept' in source, 'main.rs must use std::io and accept connections.'
    assert '/home/user/service_config.txt' in source, 'main.rs must read the required configuration file.'
    assert not re.search(r'\b(?:extern\s+crate|use)\s+(?:tokio|hyper|actix|warp|rocket)\b', source), \
        'External HTTP/runtime crates are not allowed.'

    stop_port_8443()
    for path in (CONFIG, LOG, BINARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started = time.monotonic()
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', DEPLOY],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    elapsed = time.monotonic() - started
    assert result.returncode == 0, f'deploy.sh exited with status {result.returncode}.'
    assert elapsed >= 1.8, 'deploy.sh did not actually perform the required two-second wait.'

    token = get_expected_token()
    assert re.fullmatch(r'[A-Za-z0-9]{16}', token), 'The legacy generator did not produce the token.'
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), 'api_server was not compiled.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'api_server is not a compiled native executable.'

    check_binary = '/tmp/api_server_recompiled_by_verifier'
    compile_result = subprocess.run(
        ['rustc', SOURCE, '-o', check_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, compile_result.stderr.decode(errors='replace')
    assert sha256(BINARY) == sha256(check_binary), \
        'The deployed api_server was not produced from /home/user/src/main.rs by the required rustc command.'

    pids = listener_pids()
    assert pids, 'No process is listening on port 8443 after deploy.sh exits.'
    assert any(os.path.samefile(f'/proc/{pid}/exe', BINARY) for pid in pids), \
        'The listener on port 8443 is not the compiled /home/user/api_server.'

    for _ in range(3):
        assert raw_status_request() == token.encode(), \
            'GET /status body must be strictly the token and the server must accept multiple connections.'


def test_service_config_generated():
    """Verify service_config.txt was generated and contains a token."""
    token = get_expected_token()
    assert token, 'Token value is empty.'


def test_rust_server_status_response():
    """Verify the Rust server is running on port 8443 and returns the correct token."""
    expected_token = get_expected_token()
    url = 'http://127.0.0.1:8443/status'
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f'Expected HTTP 200 OK, got {response.status}'
            body = response.read().decode('utf-8').strip()
            assert body == expected_token, f"Expected token '{expected_token}', but got '{body}'"
    except urllib.error.URLError as e:
        pytest.fail(f'Failed to connect to the Rust server at {url}: {e}')


def test_deploy_success_log():
    """Verify deploy_success.log exists and contains the correct exact message."""
    expected_token = get_expected_token()
    assert os.path.exists(LOG), f'Log file {LOG} does not exist.'
    with open(LOG, 'r') as f:
        content = f.read().strip()
    expected_content = f'Rollout complete. Active token: {expected_token}'
    assert content == expected_content, f"Log file content mismatch. Expected '{expected_content}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
