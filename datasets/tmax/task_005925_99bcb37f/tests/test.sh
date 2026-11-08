#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import time
import uuid
import signal
import subprocess
import urllib.request
import pytest


def test_scripts_exist():
    """Verify that the required scripts were created."""
    assert os.path.exists('/home/user/backend_v2.py'), "backend_v2.py is missing."
    assert os.path.exists('/home/user/proxy.py'), "proxy.py is missing."


def test_results_log_exists():
    """Verify that the results log file was created."""
    assert os.path.exists('/home/user/results.log'), "results.log does not exist."


def test_results_log_content():
    """Verify the exact responses from the curl commands in the results log."""
    with open('/home/user/results.log', 'r') as f:
        content = f.read()

    # Normalize newlines to handle both concatenated and newline-separated outputs
    normalized_content = content.replace('\n', '').replace('\r', '')
    expected_content = "V1 Legacy APIV1 Legacy APIollehWORLDV1 Legacy API"

    assert normalized_content == expected_content, (
        f"Log file contents do not match expected responses.\n"
        f"Expected (normalized): {expected_content}\n"
        f"Actual (normalized): {normalized_content}\n"
        f"Raw content: {repr(content)}"
    )


def kill_port_listeners(ports):
    """Kill processes currently listening on the task's dedicated ports."""
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != '0A':
                        continue
                    port = int(fields[1].rsplit(':', 1)[1], 16)
                    if port in ports:
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir('/proc'):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def post(port, body, version=None, extra_headers=None):
    headers = {'Content-Type': 'text/plain'}
    if version is not None:
        headers['X-API-Version'] = version
    if extra_headers:
        headers.update(extra_headers)
    request = urllib.request.Request(
        f'http://localhost:{port}/',
        data=body.encode('utf-8'),
        headers=headers,
        method='POST',
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        assert response.status == 200
        return response.read().decode('utf-8')


def wait_for(port, body, expected, version=None, processes=()):
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        for process in processes:
            if process.poll() is not None:
                pytest.fail(f'Server process exited early with status {process.returncode}')
        try:
            if post(port, body, version) == expected:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f'Server on port {port} did not become ready: {last_error!r}')


def test_live_backends_and_semver_proxy():
    """Execute the submitted programs and test fresh, non-hardcoded requests."""
    for path in ('/home/user/backend_v2.py', '/home/user/proxy.py'):
        assert os.path.isfile(path), f'{path} is not a regular file'

    kill_port_listeners({8000, 8001, 8002})
    processes = []
    try:
        v1 = subprocess.Popen(
            [sys.executable, '/home/user/backend_v1.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        v2 = subprocess.Popen(
            [sys.executable, '/home/user/backend_v2.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        processes.extend((v1, v2))

        wait_for(8001, 'readiness', 'V1 Legacy API', processes=processes)
        wait_for(8002, 'ECHO readiness', 'readiness', processes=processes)

        token = uuid.uuid4().hex
        echo_arg = f'echo-{token} with spaces'
        reverse_arg = f'Reverse-{token}-123'
        upper_arg = f'Upper-{token}-mix'
        assert post(8002, f'ECHO {echo_arg}') == echo_arg
        assert post(8002, f'REVERSE {reverse_arg}') == reverse_arg[::-1]
        assert post(8002, f'UPPER {upper_arg}') == upper_arg.upper()
        assert post(8002, f'UNKNOWN {token}') == 'ERROR'
        assert post(8002, 'ECHO') == 'ERROR'
        assert post(8002, '') == 'ERROR'

        proxy = subprocess.Popen(
            [sys.executable, '/home/user/proxy.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        processes.append(proxy)
        wait_for(8000, f'ECHO ready-{token}', f'ready-{token}', '2.0.0', processes)

        # Missing and all pre-2.0.0 versions must reach the legacy backend.
        assert post(8000, f'ECHO missing-{token}') == 'V1 Legacy API'
        for version in ('0.99.99', '1.9.9', '1.12.0', '1.999.999'):
            assert post(8000, f'REVERSE legacy-{token}', version) == 'V1 Legacy API'

        # Fresh values ensure the proxy forwards bodies and uses numeric SemVer.
        proxy_echo = f'proxy echo {token}'
        proxy_reverse = f'ProxyReverse-{token}'
        proxy_upper = f'proxyUpper-{token}'
        assert post(8000, f'ECHO {proxy_echo}', '2.0.0', {'X-Test-Token': token}) == proxy_echo
        assert post(8000, f'REVERSE {proxy_reverse}', '2.10.1') == proxy_reverse[::-1]
        assert post(8000, f'UPPER {proxy_upper}', '10.0.0') == proxy_upper.upper()
        assert post(8000, f'NOPE {token}', '3.4.5') == 'ERROR'

        for process in processes:
            assert process.poll() is None, 'A required server stopped while being tested'
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
        for process in reversed(processes):
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
