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
import signal
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import quote

import pytest
import requests

SERVER_PROCESS = None


def listener_pids(ports):
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    port = int(local_address.rsplit(':', 1)[1], 16)
                    if state == '0A' and port in ports:
                        socket_inodes.add(inode)
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_listeners():
    pids = listener_pids({8080, 8081})
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, deadline):
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            pytest.fail(f'/app/start.sh exited early with status {SERVER_PROCESS.returncode}')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f'Service did not begin listening on 127.0.0.1:{port}')


@pytest.fixture(scope='session', autouse=True)
def launch_from_start_script():
    global SERVER_PROCESS
    start_script = Path('/app/start.sh')
    assert start_script.is_file(), '/app/start.sh is missing'
    assert os.access(start_script, os.X_OK), '/app/start.sh is not executable'
    assert Path('/app/artifacts').is_dir(), '/app/artifacts must be a directory, not a file'
    assert Path('/app/mini_http_framework/parser.py').is_file(), 'Vendored parser is missing'

    stop_existing_listeners()
    SERVER_PROCESS = subprocess.Popen(
        ['/app/start.sh'],
        cwd='/app',
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    wait_for_port(8080, deadline)
    wait_for_port(8081, deadline)
    assert SERVER_PROCESS.poll() is None, '/app/start.sh did not stay running'
    yield
    # The task requires the launched server to remain running, so do not stop it.


def test_extract_filename_varied_headers():
    sys.path.insert(0, '/app')
    from mini_http_framework.parser import extract_filename

    marker = uuid.uuid4().hex
    cases = [
        (f'form-data; name="file"; filename="build log {marker}.txt"',
         f'build log {marker}.txt'),
        (f'form-data; filename="release candidate {marker}.tar.gz"; name="artifact"',
         f'release candidate {marker}.tar.gz'),
        (f'attachment; filename="nightly build {marker}.log"',
         f'nightly build {marker}.log'),
    ]
    for header, expected in cases:
        assert extract_filename(header) == expected


def test_tcp_admin_check():
    host = '127.0.0.1'
    port = 8081
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(b'PING\n')
            response = s.recv(1024).decode('utf-8')
            assert response.strip() == 'PONG', f'Expected PONG, got {response!r}'
    except ConnectionRefusedError:
        pytest.fail(f'Connection refused to TCP Admin service at {host}:{port}. Is the server running?')
    except socket.timeout:
        pytest.fail(f'Connection timed out to TCP Admin service at {host}:{port}.')


def test_http_upload_download_and_filesystem():
    base_url = 'http://127.0.0.1:8080'
    headers = {'Authorization': 'Bearer dev-token-123'}
    marker = uuid.uuid4().hex

    unauthorized = requests.get(f'{base_url}/artifact/missing-{marker}', timeout=5)
    assert unauthorized.status_code == 401

    filenames = [
        f'build log {marker}.txt',
        f'release candidate {marker}.log',
        f'ci output part {marker}.dat',
    ]
    for index, filename in enumerate(filenames):
        uploaded_content = f'dynamic upload payload {marker} number {index}'.encode()
        upload_resp = requests.post(
            f'{base_url}/upload',
            headers=headers,
            files={'file': (filename, uploaded_content)},
            timeout=5,
        )
        assert upload_resp.status_code == 200, (
            f'Upload failed with status {upload_resp.status_code}: {upload_resp.text}'
        )

        stored_path = Path('/app/artifacts') / filename
        assert stored_path.is_file(), f'Upload did not create {stored_path}'
        assert stored_path.read_text() == 'dummy content'

        download_resp = requests.get(
            f'{base_url}/artifact/{quote(filename)}', headers=headers, timeout=5
        )
        assert download_resp.status_code == 200, (
            f'Download failed with status {download_resp.status_code}: {download_resp.text}'
        )

    missing = requests.get(
        f'{base_url}/artifact/{quote("missing artifact " + marker)}',
        headers=headers,
        timeout=5,
    )
    assert missing.status_code == 404
    assert SERVER_PROCESS.poll() is None, 'Server stopped running during verification'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
