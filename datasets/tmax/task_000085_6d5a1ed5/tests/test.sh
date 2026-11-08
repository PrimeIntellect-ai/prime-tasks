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
import json
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

APP = Path('/home/user/app')
LIB = APP / 'libgateway_plugins.so'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def wait_for_listener(port, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def exercise_library(path, full):
    helper = r'''
import ctypes, secrets, sys, time
lib = ctypes.CDLL(sys.argv[1])
try:
    fn = lib.process_request
except AttributeError:
    raise AssertionError('process_request is not exported')
fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
fn.restype = ctypes.c_int

def call(ip, path):
    return fn(ip.encode(), path.encode())

def expect(ip, path, wanted):
    got = call(ip, path)
    assert got == wanted, '%r, %r: expected %d, got %d' % (ip, path, wanted, got)

token = secrets.token_hex(12)
octets = [int(token[i:i+2], 16) for i in (0, 2, 4)]
ip_a = '10.%d.%d.%d' % (octets[0], octets[1], octets[2])
ip_b = '172.20.%d.%d' % (octets[1], octets[2])
ip_c = '192.168.%d.%d' % (octets[2], octets[0])
expect(ip_a, '/api/v2/' + token, 403)
expect(ip_a, '/' + token, 403)
expect(ip_a, '/api/v1', 403)
expect(ip_a, '/api/v1x/' + token, 403)
expect(ip_a, '/api/v1/' + token, 200)
expect(ip_a, '/api/v1/', 200)
expect(ip_a, '/api/v1/data/' + token, 200)

# Interleave two clients so the limit must be maintained independently per IP.
for expected_ip in (ip_a, ip_b, ip_a, ip_b, ip_a, ip_b):
    expect(expected_ip, '/api/v1/data', 200)
expect(ip_a, '/api/v1/data', 429)
expect(ip_b, '/api/v1/data', 429)
expect(ip_c, '/api/v1/data', 200)
# Limiting data must not affect another valid path.
expect(ip_a, '/api/v1/' + token + '/other', 200)

if sys.argv[2] == 'full':
    time.sleep(2.15)
    expect(ip_a, '/api/v1/data', 200)
'''
    helper_path = '/tmp/exercise_plugin.py'
    Path(helper_path).write_text(helper)
    result = run(['python3', helper_path, str(path), 'full' if full else 'quick'],
                 timeout=8)
    assert result.returncode == 0, result.stdout


def test_required_files_exist():
    required_files = [
        APP / 'plugin.c',
        APP / 'libgateway_plugins.so',
        APP / 'test_plugin.c',
        APP / 'start_services.sh',
        Path('/home/user/test_results.log'),
    ]
    for file_path in required_files:
        assert file_path.is_file(), f'Required file {file_path} is missing.'


def test_test_results_log_content():
    log_path = Path('/home/user/test_results.log')
    assert log_path.is_file(), f'{log_path} is missing.'
    content = log_path.read_text(errors='replace')
    assert 'ALL TESTS PASSED' in content, \
        f"'{log_path}' does not contain 'ALL TESTS PASSED'."


def test_plugin_source_and_shared_library_implement_abi():
    rebuilt = Path('/tmp/plugin_from_submitted_source.so')
    result = run(['gcc', '-shared', '-fPIC', '-pthread', str(APP / 'plugin.c'),
                  '-o', str(rebuilt)], timeout=15)
    assert result.returncode == 0, 'plugin.c did not compile as a shared library:\n' + result.stdout

    # Exercise code rebuilt from plugin.c, including expiry of the rolling window.
    exercise_library(rebuilt, True)
    # Also exercise the exact artifact that the gateway is expected to load.
    exercise_library(LIB, False)


def test_submitted_unit_test_really_runs():
    test_bin = '/tmp/submitted_test_plugin'
    result = run([
        'gcc', '-pthread', str(APP / 'test_plugin.c'), '-L' + str(APP),
        '-Wl,-rpath,' + str(APP), '-lgateway_plugins', '-ldl', '-o', test_bin
    ], timeout=15)
    assert result.returncode == 0, 'test_plugin.c did not compile:\n' + result.stdout
    result = run([test_bin], cwd=str(APP), timeout=10)
    assert result.returncode == 0, 'Submitted unit test failed:\n' + result.stdout
    assert 'ALL TESTS PASSED' in result.stdout, \
        'Submitted unit test did not report ALL TESTS PASSED when executed by the verifier.'


def test_startup_script_launches_the_required_services():
    syntax = run(['bash', '-n', str(APP / 'start_services.sh')], timeout=5)
    assert syntax.returncode == 0, syntax.stdout

    # Stop whatever was serving the ports, then require the submitted startup script
    # to recreate both services. This prevents an unrelated prestarted fake server
    # from satisfying the HTTP checks.
    old_pids = listener_pids(8080) | listener_pids(8081)
    for pid in old_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and (listener_pids(8080) or listener_pids(8081)):
        time.sleep(0.1)
    for pid in old_pids:
        if pid in listener_pids(8080) or pid in listener_pids(8081):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    result = run(['bash', str(APP / 'start_services.sh')], cwd=str(APP), timeout=8)
    assert result.returncode == 0, 'start_services.sh failed:\n' + result.stdout

    gateway_pids = wait_for_listener(8080)
    backend_pids = wait_for_listener(8081)
    assert gateway_pids, 'No service is listening on port 8080 after start_services.sh.'
    assert backend_pids, 'No service is listening on port 8081 after start_services.sh.'

    expected_gateway = os.path.realpath(APP / 'gateway_bin')
    gateway_matches = []
    for pid in gateway_pids:
        try:
            gateway_matches.append(os.path.realpath(f'/proc/{pid}/exe') == expected_gateway)
        except OSError:
            pass
    assert any(gateway_matches), 'Port 8080 is not served by /home/user/app/gateway_bin.'

    backend_matches = []
    for pid in backend_pids:
        try:
            cmdline = Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ')
            backend_matches.append(b'/home/user/app/backend.py' in cmdline)
        except OSError:
            pass
    assert any(backend_matches), 'Port 8081 is not served by /home/user/app/backend.py.'


def test_gateway_randomized_proxy_and_validation():
    token = secrets.token_hex(10)
    valid_path = '/api/v1/' + token
    invalid_paths = [
        '/api/v2/' + token,
        '/api/' + token,
        '/api/v1x/' + token,
    ]
    for path in invalid_paths:
        resp = requests.get('http://127.0.0.1:8080' + path, timeout=2)
        assert resp.status_code == 403, (path, resp.status_code, resp.text)

    resp = requests.get('http://127.0.0.1:8080' + valid_path, timeout=2)
    assert resp.status_code == 200, (resp.status_code, resp.text)
    body = resp.json()
    assert body == {'status': 'ok', 'path': valid_path}, body


def test_gateway_validation_rejection():
    url = 'http://127.0.0.1:8080/api/v2/test'
    try:
        resp = requests.get(url, timeout=2)
        assert resp.status_code == 403, f'Expected 403 Forbidden for {url}, got {resp.status_code}. Response: {resp.text}'
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Connection to Gateway at {url} failed: {e}')


def test_gateway_validation_acceptance():
    url = 'http://127.0.0.1:8080/api/v1/ping'
    try:
        resp = requests.get(url, timeout=2)
        assert resp.status_code == 200, f'Expected 200 OK for {url}, got {resp.status_code}. Response: {resp.text}'
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Connection to Gateway at {url} failed: {e}')


def test_gateway_rate_limiting():
    url = 'http://127.0.0.1:8080/api/v1/data'
    time.sleep(2.1)
    try:
        resp1 = requests.get(url, timeout=2)
        assert resp1.status_code == 200, f'Request 1 expected 200 OK, got {resp1.status_code}. Response: {resp1.text}'
        resp2 = requests.get(url, timeout=2)
        assert resp2.status_code == 200, f'Request 2 expected 200 OK, got {resp2.status_code}. Response: {resp2.text}'
        resp3 = requests.get(url, timeout=2)
        assert resp3.status_code == 200, f'Request 3 expected 200 OK, got {resp3.status_code}. Response: {resp3.text}'
        resp4 = requests.get(url, timeout=2)
        assert resp4.status_code == 429, f'Request 4 expected 429 Too Many Requests, got {resp4.status_code}. Response: {resp4.text}'
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Rate limiting requests to {url} failed: {e}')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
