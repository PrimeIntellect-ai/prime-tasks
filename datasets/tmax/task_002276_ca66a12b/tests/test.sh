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
import re
import secrets
import signal
import socket
import subprocess
import time

import pytest
import requests

ROUTES_PATH = '/home/user/routes.txt'
START_PATH = '/home/user/start_daemon.sh'
MONITOR_PATH = '/home/user/monitor.sh'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def extract_config():
    result = run(['tesseract', '/app/config_snapshot.png', 'stdout'], timeout=20)
    assert result.returncode == 0, result.stderr
    port_match = re.search(r'BIND_PORT\s*=\s*(\d+)', result.stdout)
    token_match = re.search(r'AUTH_TOKEN\s*=\s*([A-Za-z0-9_.-]+)', result.stdout)
    assert port_match, f'Could not OCR BIND_PORT from snapshot: {result.stdout!r}'
    assert token_match, f'Could not OCR AUTH_TOKEN from snapshot: {result.stdout!r}'
    return int(port_match.group(1)), token_match.group(1)


def extract_legacy_routes():
    result = run(['/app/legacy_admin_cli'], input='admin\nlegacy2024\n', timeout=10)
    assert result.returncode == 0, result.stderr
    routes = {}
    for line in result.stdout.splitlines():
        match = re.fullmatch(r'([A-Za-z0-9_.-]+):(\d{1,3}(?:\.\d{1,3}){3})', line.strip())
        if match:
            routes[match.group(1)] = match.group(2)
    assert routes, f'Legacy CLI returned no routing rules: {result.stdout!r}'
    return routes


BIND_PORT, AUTH_TOKEN = extract_config()
EXPECTED_ROUTES = extract_legacy_routes()


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])
    pids = set()
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
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def cmdline(pid):
    try:
        return open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def wait_for_listener(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(BIND_PORT)
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def launch_daemon():
    result = run(['bash', START_PATH], timeout=10)
    assert result.returncode == 0, f'start_daemon.sh failed: {result.stderr}'
    pids = wait_for_listener()
    assert pids, f'No process is listening on OCR-derived port {BIND_PORT}'
    assert any('socat' in cmdline(pid) for pid in pids), \
        f'The listener on port {BIND_PORT} is not socat: {[cmdline(p) for p in pids]}'
    return pids


def stop_listener():
    for pid in listener_pids(BIND_PORT):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listener_pids(BIND_PORT) and time.time() < deadline:
        time.sleep(0.1)


def read_sources():
    sources = {}
    for root, _, files in os.walk('/home/user'):
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.getsize(path) <= 1024 * 1024:
                    sources[path] = open(path, errors='replace').read()
            except (OSError, UnicodeError):
                pass
    return sources


def test_routes_file():
    """Verify that the routes.txt file was correctly generated."""
    routes_path = '/home/user/routes.txt'
    assert os.path.isfile(routes_path), f"The routes file {routes_path} is missing."
    with open(routes_path, 'r') as f:
        content = f.read()

    assert "app1:192.168.1.10" in content, "Route for app1 is missing or incorrect."
    assert "app2:192.168.1.11" in content, "Route for app2 is missing or incorrect."
    assert "db_main:10.0.0.5" in content, "Route for db_main is missing or incorrect."
    for key, ip in EXPECTED_ROUTES.items():
        assert f'{key}:{ip}' in content, f'Derived legacy route {key}:{ip} is missing.'


def test_required_automation_and_launcher():
    assert os.path.isfile(START_PATH), f'The launcher {START_PATH} is missing.'
    assert os.access(START_PATH, os.X_OK), f'The launcher {START_PATH} is not executable.'
    first_line = open(START_PATH, errors='replace').readline()
    assert 'bash' in first_line, 'start_daemon.sh is not a Bash script.'

    sources = read_sources()
    ocr_sources = [text for text in sources.values()
                   if re.search(r'(^|[\s/])tesseract([\s]|$)', text) and '/app/config_snapshot.png' in text]
    cli_sources = [text for text in sources.values()
                   if '/app/legacy_admin_cli' in text and re.search(r'(^|[\s/])expect([\s]|$)', text)]
    assert ocr_sources, 'No submitted script programmatically OCRs /app/config_snapshot.png with tesseract.'
    assert cli_sources, 'No submitted script automates /app/legacy_admin_cli using expect.'

    first_pids = launch_daemon()
    second_pids = launch_daemon()
    assert not (first_pids & second_pids), \
        'A second launch did not terminate and replace the existing daemon listener.'


def test_daemon_health():
    """Test the /health endpoint."""
    try:
        response = requests.get('http://127.0.0.1:8443/health', timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the daemon on port 8443: {e}")

    assert response.status_code == 200, f"Expected status 200 for /health, got {response.status_code}"
    assert response.text.strip() == "OK", f"Expected body 'OK' for /health, got {response.text}"


def test_daemon_lookup_missing_auth():
    """Test the /lookup endpoint without an auth token."""
    try:
        response = requests.get('http://127.0.0.1:8443/lookup?service=app2', timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the daemon on port 8443: {e}")

    assert response.status_code == 403, f"Expected status 403 for missing auth, got {response.status_code}"


def test_daemon_lookup_correct_auth():
    """Test the /lookup endpoint with the correct auth token."""
    headers = {'X-Auth-Token': 'super-secret-77X'}
    try:
        response = requests.get('http://127.0.0.1:8443/lookup?service=app2', headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the daemon on port 8443: {e}")

    assert response.status_code == 200, f"Expected status 200 for correct auth, got {response.status_code}"
    assert "192.168.1.11" in response.text, f"Expected IP '192.168.1.11' in response, got {response.text}"


def test_daemon_lookup_unknown_service():
    """Test the /lookup endpoint with an unknown service."""
    headers = {'X-Auth-Token': 'super-secret-77X'}
    try:
        response = requests.get('http://127.0.0.1:8443/lookup?service=unknown', headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the daemon on port 8443: {e}")

    assert response.status_code == 404, f"Expected status 404 for unknown service, got {response.status_code}"


def test_dynamic_route_file_and_derived_credentials():
    original = open(ROUTES_PATH).read()
    key = 'probe_' + secrets.token_hex(8)
    unknown = 'missing_' + secrets.token_hex(8)
    ip = f'172.31.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'
    try:
        with open(ROUTES_PATH, 'a') as f:
            if original and not original.endswith('\n'):
                f.write('\n')
            f.write(f'{key}:{ip}\n')

        good = requests.get(f'http://127.0.0.1:{BIND_PORT}/lookup?service={key}',
                            headers={'X-Auth-Token': AUTH_TOKEN}, timeout=5)
        assert good.status_code == 200
        assert good.text.strip() == ip

        bad = requests.get(f'http://127.0.0.1:{BIND_PORT}/lookup?service={key}',
                           headers={'X-Auth-Token': 'wrong-' + secrets.token_hex(8)}, timeout=5)
        assert bad.status_code == 403

        missing = requests.get(f'http://127.0.0.1:{BIND_PORT}/lookup?service={unknown}',
                               headers={'X-Auth-Token': AUTH_TOKEN}, timeout=5)
        assert missing.status_code == 404
    finally:
        with open(ROUTES_PATH, 'w') as f:
            f.write(original)


def test_http_responses_use_crlf():
    with socket.create_connection(('127.0.0.1', BIND_PORT), timeout=5) as sock:
        sock.sendall(b'GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
        sock.settimeout(2)
        chunks = []
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
    raw = b''.join(chunks)
    assert raw.startswith(b'HTTP/1.1 200 OK\r\n'), raw
    assert b'\r\n\r\n' in raw, raw
    head = raw.split(b'\r\n\r\n', 1)[0]
    assert b'\n' not in head.replace(b'\r\n', b''), 'HTTP headers contain non-CRLF line endings.'


def test_monitor_script():
    """Verify that the monitor.sh script exists and runs successfully."""
    monitor_path = '/home/user/monitor.sh'
    assert os.path.isfile(monitor_path), f"The monitor script {monitor_path} is missing."
    assert os.access(monitor_path, os.X_OK), f"The monitor script {monitor_path} is not executable."

    result = subprocess.run(['bash', monitor_path], capture_output=True)
    assert result.returncode == 0, f"Monitor script failed with exit code {result.returncode}. stderr: {result.stderr.decode()}"


def test_monitor_detects_failure_and_service_is_restored():
    stop_listener()
    try:
        assert not listener_pids(BIND_PORT), 'Could not stop daemon for the negative monitor test.'
        result = run(['bash', MONITOR_PATH], timeout=10)
        assert result.returncode == 1, \
            f'monitor.sh must exit 1 while health endpoint is down; got {result.returncode}'
    finally:
        launch_daemon()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
