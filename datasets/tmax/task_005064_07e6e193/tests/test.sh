#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import json
import os
import socket
import ssl
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

import pytest

BASE = Path('/home/user/monitor_alert_sys')
SETUP = Path('/home/user/setup_env.py')
SERVER = BASE / 'server.py'
MANAGER = BASE / 'service_manager.py'
MONITOR = BASE / 'alert_monitor.py'
PID_FILE = BASE / 'server.pid'
ALERT = BASE / 'alerts/latest_alert.txt'
STATUS = Path('/home/user/system_status.json')
URL = 'https://127.0.0.1:8443/health.json'


def https_get(path='/health.json', timeout=5):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen('https://127.0.0.1:8443' + path, context=ctx, timeout=timeout) as response:
        return response.status, response.read()


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    try:
        stat = Path(f'/proc/{pid}/stat').read_text()
        if stat.split()[2] == 'Z':
            return False
    except (OSError, IndexError):
        pass
    return True


def wait_for_dead(pid, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return
        time.sleep(0.1)
    pytest.fail(f'Process {pid} did not terminate')


def wait_for_https(timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = https_get(timeout=1)
            if status == 200:
                return body
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f'HTTPS service did not become ready: {last_error}')


def wait_for_port_down(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.3)
        try:
            result = sock.connect_ex(('127.0.0.1', 8443))
        finally:
            sock.close()
        if result != 0:
            return
        time.sleep(0.1)
    pytest.fail('Port 8443 remained reachable after stop')


def read_pid():
    assert PID_FILE.exists(), f'{PID_FILE} does not exist'
    value = PID_FILE.read_text().strip()
    assert value.isdigit(), f'PID file does not contain a valid integer: {value!r}'
    return int(value)


def run_script(path, *args, timeout=15):
    return subprocess.run(
        [sys.executable, str(path), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def assert_server_pid(pid):
    assert process_alive(pid), f'Process {pid} is not running'
    cmdline_path = Path(f'/proc/{pid}/cmdline')
    assert cmdline_path.exists(), f'No cmdline is available for PID {pid}'
    cmdline = cmdline_path.read_bytes().replace(b'\0', b' ').decode(errors='replace')
    assert str(SERVER) in cmdline or 'server.py' in cmdline, (
        f'PID {pid} was not launched from server.py: {cmdline!r}'
    )


def assert_pid_listens_on_loopback(pid):
    socket_inodes = set()
    fd_dir = Path(f'/proc/{pid}/fd')
    for fd in fd_dir.iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith('socket:[') and target.endswith(']'):
            socket_inodes.add(target[8:-1])

    found = False
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        if not Path(table).exists():
            continue
        for line in Path(table).read_text().splitlines()[1:]:
            fields = line.split()
            if len(fields) < 10 or fields[9] not in socket_inodes or fields[3] != '0A':
                continue
            address, port = fields[1].split(':')
            if int(port, 16) != 8443:
                continue
            assert table.endswith('/tcp') and address == '0100007F', (
                f'server.py must bind port 8443 specifically to 127.0.0.1; got {address}'
            )
            found = True
    assert found, f'PID {pid} does not own a loopback listener on port 8443'


# Original final-state assertions.
def test_final_report_json():
    report_path = '/home/user/final_report.json'
    assert os.path.exists(report_path), f'{report_path} does not exist.'
    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{report_path} is not valid JSON.')
    assert 'alert_file_content' in data, "Missing 'alert_file_content' in final_report.json"
    assert 'service_recovered' in data, "Missing 'service_recovered' in final_report.json"
    assert data['alert_file_content'] == 'ALERT: Service down', (
        f"Expected alert_file_content to be 'ALERT: Service down', got '{data['alert_file_content']}'"
    )
    assert data['service_recovered'] is True, (
        f"Expected service_recovered to be true, got {data['service_recovered']}"
    )


def test_symlink_exists():
    symlink_path = '/home/user/monitor_alert_sys/docroot/health.json'
    target_path = '/home/user/system_status.json'
    assert os.path.islink(symlink_path), f'{symlink_path} is not a symlink.'
    assert os.readlink(symlink_path) == target_path, f'{symlink_path} does not point to {target_path}.'


def test_server_running_and_responds():
    try:
        status, body = https_get()
        assert status == 200, f'Expected HTTP 200, got {status}'
        try:
            data = json.loads(body.decode('utf-8'))
        except json.JSONDecodeError:
            pytest.fail('Response body is not valid JSON.')
        assert data.get('status') == 'ok', f"Expected {{'status': 'ok'}}, got {data}"
    except Exception as exc:
        pytest.fail(f'Failed to connect to {URL} or read response: {exc}')


def test_pid_file_and_process():
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f'Process with PID {pid} is not running.')
    comm_file = f'/proc/{pid}/comm'
    if os.path.exists(comm_file):
        with open(comm_file, 'r') as f:
            comm = f.read().strip()
        assert 'python' in comm.lower(), (
            f'Process {pid} is running but does not appear to be Python (comm: {comm}).'
        )


def test_alert_file():
    assert ALERT.exists(), f'{ALERT} does not exist.'
    content = ALERT.read_text().strip()
    assert content == 'ALERT: Service down', (
        f"Expected alert file content to be 'ALERT: Service down', got '{content}'"
    )


def test_required_scripts_and_full_lifecycle():
    for path in (SETUP, SERVER, MANAGER, MONITOR):
        assert path.is_file(), f'Required Python script {path} is missing'
        compiled = subprocess.run(
            [sys.executable, '-m', 'py_compile', str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compiled.returncode == 0, f'{path} is not valid Python: {compiled.stderr}'

    # Exercise the submitted manager rather than trusting the pre-existing PID file.
    initial_pid = read_pid()
    running_status = run_script(MANAGER, 'status')
    stopped = run_script(MANAGER, 'stop')
    wait_for_dead(initial_pid)
    wait_for_port_down()
    assert not PID_FILE.exists(), 'service_manager.py stop did not remove server.pid'
    stopped_status = run_script(MANAGER, 'status')
    running_observation = (running_status.returncode, running_status.stdout.strip(), running_status.stderr.strip())
    stopped_observation = (stopped_status.returncode, stopped_status.stdout.strip(), stopped_status.stderr.strip())
    assert running_observation != stopped_observation, (
        'service_manager.py status did not distinguish a running service from a stopped service'
    )

    # setup_env.py must be repeatable and must create all specified resources.
    for attempt in range(2):
        result = run_script(SETUP, timeout=30)
        assert result.returncode == 0, f'setup_env.py failed on run {attempt + 1}: {result.stderr}'
    for directory in ('logs', 'certs', 'docroot', 'alerts'):
        assert (BASE / directory).is_dir(), f'Missing required directory: {BASE / directory}'
    assert STATUS.read_bytes() == b'{"status": "ok"}', 'system_status.json does not contain the exact required text'
    health = BASE / 'docroot/health.json'
    assert health.is_symlink(), 'health.json is not a symbolic link after setup'
    assert os.readlink(health) == str(STATUS), 'health.json has the wrong symlink target'

    key = BASE / 'certs/server.key'
    cert = BASE / 'certs/server.crt'
    assert key.is_file() and cert.is_file(), 'TLS key or certificate is missing'
    key_check = subprocess.run(['openssl', 'pkey', '-in', str(key), '-check', '-noout'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert key_check.returncode == 0, 'server.key is not a valid private key'
    cert_check = subprocess.run(['openssl', 'x509', '-in', str(cert), '-noout', '-text'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert cert_check.returncode == 0, 'server.crt is not a valid X.509 certificate'
    assert 'rsaEncryption' in cert_check.stdout or 'RSA' in cert_check.stdout, 'server.crt does not contain an RSA public key'

    started = run_script(MANAGER, 'start')
    assert started.returncode == 0, f'service_manager.py start failed: {started.stderr}'
    wait_for_https()
    pid = read_pid()
    assert_server_pid(pid)
    assert_pid_listens_on_loopback(pid)

    # Derive a fresh response so a fixed fake {"status":"ok"} endpoint cannot pass.
    nonce = uuid.uuid4().hex
    probe = BASE / 'docroot' / f'verifier-{nonce}.txt'
    payload = f'dynamic-{uuid.uuid4().hex}'.encode()
    probe.write_bytes(payload)
    try:
        status, body = https_get('/' + probe.name)
        assert status == 200 and body == payload, 'server.py is not serving files from the required docroot'
    finally:
        probe.unlink(missing_ok=True)

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(('127.0.0.1', 8443), timeout=3) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    expected_der = ssl.PEM_cert_to_DER_cert(cert.read_text())
    import base64
    assert served_der == base64.b64decode(expected_der), 'server.py is not using certs/server.crt'

    # On a healthy request, the monitor must exit cleanly without alerting or replacing the service.
    ALERT.unlink(missing_ok=True)
    healthy_pid = read_pid()
    healthy = run_script(MONITOR, timeout=15)
    assert healthy.returncode == 0, f'alert_monitor.py failed while service was healthy: {healthy.stderr}'
    assert not ALERT.exists(), 'alert_monitor.py raised a down alert while HTTPS was healthy'
    assert read_pid() == healthy_pid and process_alive(healthy_pid), 'healthy monitoring restarted or stopped the server'

    # Stop the service, then instrument the required manager path to prove that
    # alert_monitor.py invokes service_manager.py start during remediation.
    run_script(MANAGER, 'stop')
    wait_for_dead(healthy_pid)
    wait_for_port_down()
    ALERT.unlink(missing_ok=True)

    marker = Path('/tmp') / f'manager-invocation-{uuid.uuid4().hex}.jsonl'
    backup = MANAGER.with_name(f'.service_manager-{uuid.uuid4().hex}.py')
    original_mode = MANAGER.stat().st_mode
    os.replace(MANAGER, backup)
    wrapper = (
        '#!/usr/bin/env python3\n'
        'import json, os, sys\n'
        f"with open({str(marker)!r}, 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        f"os.execv(sys.executable, [sys.executable, {str(backup)!r}] + sys.argv[1:])\n"
    )
    MANAGER.write_text(wrapper)
    os.chmod(MANAGER, original_mode | 0o755)
    try:
        remediation = run_script(MONITOR, timeout=20)
    finally:
        MANAGER.unlink(missing_ok=True)
        os.replace(backup, MANAGER)
    assert remediation.returncode == 0, f'alert_monitor.py failed during remediation: {remediation.stderr}'
    assert marker.exists(), 'alert_monitor.py did not invoke the required service_manager.py path'
    calls = [json.loads(line) for line in marker.read_text().splitlines()]
    marker.unlink(missing_ok=True)
    assert ['start'] in calls, f'alert_monitor.py did not invoke service_manager.py start; calls were {calls}'
    assert ALERT.read_bytes() == b'ALERT: Service down', 'Outage alert does not contain the exact required text'

    wait_for_https()
    recovered_pid = read_pid()
    assert_server_pid(recovered_pid)
    assert_pid_listens_on_loopback(recovered_pid)
    status, body = https_get()
    assert status == 200 and json.loads(body.decode()) == {'status': 'ok'}, 'Recovered service has the wrong health response'
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
