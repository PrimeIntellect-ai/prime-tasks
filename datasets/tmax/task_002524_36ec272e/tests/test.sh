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
import ast
import os
import secrets
import shutil
import socket
import ssl
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

STATE_FILE = Path('/home/user/monitor_data/qemu_state.bin')
DATA_DIR = STATE_FILE.parent
SERVICE_FILE = Path('/home/user/sre_service.py')
CERT_FILE = Path('/home/user/certs/server.crt')
KEY_FILE = Path('/home/user/certs/server.key')
PROBE_FILE = Path('/app/qemu_probe')
HTTPS_URL = 'https://127.0.0.1:8443/health'
QUOTA = 1048576


def https_get():
    try:
        return requests.get(HTTPS_URL, verify=False, timeout=5, headers={'Connection': 'close'})
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to {HTTPS_URL}: {exc}')


def tcp_status():
    try:
        with socket.create_connection(('127.0.0.1', 9090), timeout=5) as sock:
            sock.settimeout(5)
            sock.sendall(b'STATUS\n')
            chunks = []
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                chunks.append(chunk)
            return b''.join(chunks).decode('utf-8')
    except Exception as exc:
        pytest.fail(f'Failed to query 127.0.0.1:9090: {exc}')


def regular_file_total(root):
    total = 0
    for current, _, files in os.walk(root):
        for name in files:
            path = os.path.join(current, name)
            if os.path.isfile(path) and not os.path.islink(path):
                total += os.path.getsize(path)
    return total


def test_required_artifacts_and_state():
    assert SERVICE_FILE.is_file(), f'{SERVICE_FILE} does not exist or is not a regular file'
    source = SERVICE_FILE.read_text(encoding='utf-8')
    assert source.strip(), f'{SERVICE_FILE} is empty'
    ast.parse(source, filename=str(SERVICE_FILE))

    running = False
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmdline = (proc / 'cmdline').read_bytes().split(b'\0')
        except (OSError, PermissionError):
            continue
        if str(SERVICE_FILE).encode() in cmdline:
            running = True
            break
    assert running, f'No running process has {SERVICE_FILE} in its command line'

    assert STATE_FILE.is_file(), f'State file {STATE_FILE} does not exist'
    assert STATE_FILE.read_bytes() == b'QEMU_VNC_ACTIVE', 'State file contents are not exactly QEMU_VNC_ACTIVE'
    mode = stat.S_IMODE(STATE_FILE.stat().st_mode)
    assert mode == 0o400, f'State file permissions should be 0400, got {oct(mode)}'

    assert CERT_FILE.is_file(), f'TLS certificate missing at {CERT_FILE}'
    assert KEY_FILE.is_file(), f'TLS private key missing at {KEY_FILE}'

    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', str(CERT_FILE), '-pubkey', '-noout'],
        check=True, capture_output=True
    ).stdout
    key_pub = subprocess.run(
        ['openssl', 'pkey', '-in', str(KEY_FILE), '-pubout'],
        check=True, capture_output=True
    ).stdout
    assert cert_pub == key_pub, 'server.crt and server.key do not form a matching pair'
    subprocess.run(
        ['openssl', 'verify', '-CAfile', str(CERT_FILE), str(CERT_FILE)],
        check=True, capture_output=True
    )


def test_https_health_endpoint_and_live_probe_execution():
    response = https_get()
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
    expected_body = '{"status": "UP", "target": "QEMU_VNC", "latency": "15ms"}\n'
    assert response.text == expected_body, f'Expected response body {expected_body!r}, got {response.text!r}'

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(('127.0.0.1', 8443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    file_der = ssl.PEM_cert_to_DER_cert(CERT_FILE.read_text(encoding='ascii'))
    assert served_der == file_der, 'Port 8443 is not serving the certificate at /home/user/certs/server.crt'

    nonce = 'probe-' + secrets.token_hex(24)
    backup = Path('/app') / ('.qemu_probe.verifier.' + secrets.token_hex(8))
    os.replace(PROBE_FILE, backup)
    try:
        wrapper = f'''#!/usr/bin/env python3
import os
import stat
import sys
path = '/home/user/monitor_data/qemu_state.bin'
valid = (
    os.environ.get('PROBE_TOKEN') == 'sre_uptime_55'
    and sys.argv[1:] == ['--state-file', path]
    and stat.S_IMODE(os.stat(path).st_mode) == 0o400
    and open(path, 'rb').read() == b'QEMU_VNC_ACTIVE'
)
if not valid:
    print('invalid probe invocation', file=sys.stderr)
    raise SystemExit(37)
sys.stdout.write({(nonce + chr(10))!r})
'''
        PROBE_FILE.write_text(wrapper, encoding='utf-8')
        os.chmod(PROBE_FILE, 0o755)
        dynamic = https_get()
        assert dynamic.status_code == 200, f'Expected 200 from live probe invocation, got {dynamic.status_code}'
        assert dynamic.text == nonce + '\n', 'HTTPS endpoint did not return the live probe standard output'
    finally:
        try:
            PROBE_FILE.unlink(missing_ok=True)
        finally:
            os.replace(backup, PROBE_FILE)


def test_tcp_quota_endpoint_with_runtime_sizes():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    backup_dir = Path(tempfile.mkdtemp(prefix='monitor-data-backup-', dir='/tmp'))
    moved = []
    payload = DATA_DIR / ('quota-' + secrets.token_hex(8) + '.dat')

    try:
        for entry in list(DATA_DIR.iterdir()):
            if entry != STATE_FILE:
                destination = backup_dir / entry.name
                os.replace(entry, destination)
                moved.append((destination, entry))

        response = tcp_status()
        assert response == 'QUOTA_OK\n', f"Expected 'QUOTA_OK\\n', got {response!r}"

        junk_file = DATA_DIR / 'junk.dat'
        junk_file.write_bytes(b'0' * (2 * 1024 * 1024))
        response2 = tcp_status()
        assert response2 == 'QUOTA_EXCEEDED\n', f"Expected 'QUOTA_EXCEEDED\\n', got {response2!r}"
        junk_file.unlink()

        cases = [secrets.randbelow(2) == 1 for _ in range(10)]
        cases[0] = False
        cases[1] = True
        for exceeded in cases:
            payload.unlink(missing_ok=True)
            base = regular_file_total(DATA_DIR)
            if exceeded:
                target = QUOTA + 1 + secrets.randbelow(400000)
                expected = 'QUOTA_EXCEEDED\n'
            else:
                target = max(base, 4096 + secrets.randbelow(850000))
                target = min(target, QUOTA)
                expected = 'QUOTA_OK\n'
            amount = target - base
            assert amount >= 0
            payload.write_bytes(b'x' * amount)
            actual_total = regular_file_total(DATA_DIR)
            assert (actual_total > QUOTA) == exceeded
            actual = tcp_status()
            assert actual == expected, (
                f'For runtime-generated directory size {actual_total}, '
                f'expected {expected!r}, got {actual!r}'
            )
    finally:
        payload.unlink(missing_ok=True)
        junk = DATA_DIR / 'junk.dat'
        junk.unlink(missing_ok=True)
        for source, destination in moved:
            if destination.exists() or destination.is_symlink():
                if destination.is_dir() and not destination.is_symlink():
                    shutil.rmtree(destination)
                else:
                    destination.unlink()
            os.replace(source, destination)
        shutil.rmtree(backup_dir, ignore_errors=True)


def test_file_permissions():
    assert STATE_FILE.exists(), f'State file {STATE_FILE} does not exist'
    st = os.stat(STATE_FILE)
    assert (st.st_mode & 0o777) == 0o400, f'State file permissions should be 0400, got {oct(st.st_mode & 0o777)}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
