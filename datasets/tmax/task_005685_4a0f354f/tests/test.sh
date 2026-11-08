#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import signal
import socket
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request

SERVICE_DIR = '/home/user/service'
STARTED_PROCESSES = []


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r') as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc_dir in glob.glob('/proc/[0-9]*'):
        pid = int(proc_dir.rsplit('/', 1)[1])
        if pid == os.getpid():
            continue
        for fd in glob.glob(proc_dir + '/fd/*'):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def kill_port_listener(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)

    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline:
        if not listener_pids(port):
            return
        time.sleep(0.05)
    assert not listener_pids(port), f'Could not stop the listener on port {port}.'


def start_python_service(script, port):
    assert os.path.isfile(script), f'{script} does not exist.'
    proc = subprocess.Popen(
        [sys.executable, script],
        cwd=SERVICE_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    STARTED_PROCESSES.append(proc)
    deadline = time.time() + 4
    while time.time() < deadline:
        if proc.poll() is not None:
            assert False, f'{script} exited during startup with status {proc.returncode}.'
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return proc
        except OSError:
            time.sleep(0.05)
    proc.terminate()
    assert False, f'{script} did not listen on port {port}.'


def test_config_and_secret_files():
    config_path = '/home/user/service/config.json'
    secret_path = '/home/user/service/secret.key'

    assert os.path.isfile(config_path), f'{config_path} does not exist.'
    assert os.path.isfile(secret_path), f'{secret_path} does not exist.'

    config_stat = os.stat(config_path)
    assert stat.S_IMODE(config_stat.st_mode) == 0o600, f'{config_path} permissions are not exactly 0600.'

    with open(config_path, 'r') as f:
        try:
            config_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{config_path} does not contain valid JSON.'

    expected_config = {'bind_host': '127.0.0.1', 'bind_port': 5050, 'log_file': '/home/user/service/access.log'}
    assert config_data == expected_config, f'{config_path} content does not match the expected JSON.'

    secret_stat = os.stat(secret_path)
    assert stat.S_IMODE(secret_stat.st_mode) == 0o400, f'{secret_path} permissions are not exactly 0400.'

    with open(secret_path, 'rb') as f:
        secret_content = f.read()
    assert secret_content == b'METRICS_TOKEN_xyz123', f'{secret_path} content does not match the exact expected string.'


def test_server_rejects_incorrect_permissions_and_start_artifact():
    server_script = '/home/user/service/server.py'
    config_path = '/home/user/service/config.json'
    secret_path = '/home/user/service/secret.key'
    assert os.path.isfile(server_script), f'{server_script} does not exist.'

    kill_port_listener(5050)
    results = []
    for path, bad_mode, good_mode in (
        (config_path, 0o644, 0o600),
        (secret_path, 0o600, 0o400),
    ):
        os.chmod(path, bad_mode)
        try:
            try:
                result = subprocess.run(
                    [sys.executable, server_script],
                    cwd=SERVICE_DIR,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=2,
                )
                results.append((result.returncode, result.stdout + result.stderr))
            except subprocess.TimeoutExpired:
                results.append((None, b''))
        finally:
            os.chmod(path, good_mode)
            kill_port_listener(5050)

    start_python_service(server_script, 5050)

    for returncode, output in results:
        assert returncode == 1, 'server.py must immediately exit with status 1 when a required file mode is incorrect.'
        assert output.strip(), 'server.py must print an error when rejecting incorrect file permissions.'


def test_primary_service_health():
    url = 'http://127.0.0.1:5050/health'
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f'Expected HTTP 200 from {url}, got {response.status}.'
            body = response.read().decode('utf-8')
            assert body == 'OK', f"Expected body 'OK' from {url}, got '{body}'."
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to primary service at {url}: {e}'


def test_primary_service_metrics_unauthorized():
    url = 'http://127.0.0.1:5050/metrics'
    req = urllib.request.Request(url)
    try:
        urllib.request.urlopen(req, timeout=2)
        assert False, f'Expected HTTP 403 Forbidden from {url} when no token is provided, but request succeeded.'
    except urllib.error.HTTPError as e:
        assert e.code == 403, f'Expected HTTP 403 from {url} without token, got {e.code}.'
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to primary service at {url}: {e}'


def test_primary_service_metrics_authorized():
    url = 'http://127.0.0.1:5050/metrics'
    req = urllib.request.Request(url)
    req.add_header('X-Auth-Token', 'METRICS_TOKEN_xyz123')
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f'Expected HTTP 200 from {url} with valid token, got {response.status}.'
            body = response.read().decode('utf-8')
            assert body == 'SECURE_METRICS_DATA', f"Expected body 'SECURE_METRICS_DATA' from {url}, got '{body}'."
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to primary service at {url} with token: {e}'


def test_firewall_proxy_artifact_startup():
    proxy_script = '/home/user/service/firewall_proxy.py'
    assert os.path.isfile(proxy_script), f'{proxy_script} does not exist.'
    kill_port_listener(6060)
    start_python_service(proxy_script, 6060)


def test_firewall_proxy_allowed():
    url = 'http://127.0.0.1:6060/health'
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f'Expected HTTP 200 from proxy at {url}, got {response.status}.'
            body = response.read().decode('utf-8')
            assert body == 'OK', f"Expected body 'OK' from proxy at {url}, got '{body}'."
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to firewall proxy at {url}: {e}'


def test_firewall_proxy_rejects_disallowed_source():
    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client.settimeout(1)
    try:
        client.bind(('127.0.0.2', 0))
        client.connect(('127.0.0.1', 6060))
        try:
            data = client.recv(1)
        except ConnectionResetError:
            data = b''
        except socket.timeout:
            assert False, 'Proxy did not immediately close a connection from disallowed source 127.0.0.2.'
        assert data == b'', 'Proxy sent data to a disallowed source instead of immediately closing the connection.'
    finally:
        client.close()


def test_firewall_proxy_code_for_acls():
    proxy_script = '/home/user/service/firewall_proxy.py'
    assert os.path.isfile(proxy_script), f'{proxy_script} does not exist.'
    with open(proxy_script, 'r') as f:
        content = f.read()
    assert '10.0.0.55' in content, f"Expected to find IP '10.0.0.55' in {proxy_script} for ACL checks."
    assert '127.0.0.1' in content, f"Expected to find IP '127.0.0.1' in {proxy_script} for ACL checks."


def test_monitor_script():
    monitor_script = '/home/user/service/monitor.sh'
    log_file = '/home/user/service/monitor.log'
    server_script = '/home/user/service/server.py'

    assert os.path.isfile(monitor_script), f'{monitor_script} does not exist.'
    assert os.access(monitor_script, os.X_OK), f'{monitor_script} is not executable.'

    if os.path.exists(log_file):
        os.remove(log_file)

    try:
        subprocess.run([monitor_script], check=True, timeout=5)
    except subprocess.CalledProcessError as e:
        assert False, f'Execution of {monitor_script} failed with exit code {e.returncode}.'
    except subprocess.TimeoutExpired:
        assert False, f'Execution of {monitor_script} timed out.'

    assert os.path.isfile(log_file), f'{log_file} was not created by the monitor script.'
    with open(log_file, 'r') as f:
        lines = f.readlines()
    assert len(lines) > 0, f'{log_file} is empty.'
    last_line = lines[-1].strip()
    assert last_line == '[OK] Service is healthy', f"Expected log entry '[OK] Service is healthy', got '{last_line}'."

    kill_port_listener(5050)
    failure = None
    try:
        subprocess.run([monitor_script], check=True, timeout=5)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        failure = e
    finally:
        start_python_service(server_script, 5050)

    assert failure is None, f'Execution of {monitor_script} failed while handling an unreachable service: {failure}'
    with open(log_file, 'r') as f:
        lines = f.readlines()
    assert lines[-1].strip() == '[ERROR] Service unreachable', \
        f"Expected log entry '[ERROR] Service unreachable', got '{lines[-1].strip()}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
