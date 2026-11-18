#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

REPO = '/home/user/release_prep'
EXPECTED = {"status": "ok", "version": "1.2.0"}


def fetch(url, timeout=2):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.read()


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != '0A':
                        continue
                    if int(fields[1].split(':')[1], 16) == port:
                        inodes.add(fields[9])
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
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_listeners(*ports):
    pids = set()
    for port in ports:
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    remaining = set()
    for port in ports:
        remaining.update(listener_pids(port))
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def wait_for_json(url, attempts=30):
    last_error = None
    for _ in range(attempts):
        try:
            body = fetch(url, timeout=1)
            return body, json.loads(body.decode('utf-8'))
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f'{url} did not become ready: {last_error}')


def assert_listener_executable(port, expected_executable):
    pids = listener_pids(port)
    assert pids, f'No process is listening on port {port}.'
    expected = os.path.realpath(expected_executable)
    actual = []
    for pid in pids:
        try:
            exe = os.path.realpath(f'/proc/{pid}/exe')
            actual.append(exe)
            if os.path.samefile(exe, expected):
                return
        except (FileNotFoundError, PermissionError, OSError):
            continue
    assert False, f'Port {port} is not served by {expected}; listener executables: {actual}'


def test_patch_applied():
    test_runner_path = '/home/user/release_prep/tests/test_runner.cpp'
    assert os.path.isfile(test_runner_path), f'File {test_runner_path} is missing.'
    with open(test_runner_path) as f:
        content = f.read()
    assert '// Added mock fixture initialization' in content, 'The patch was not applied to tests/test_runner.cpp.'


def test_makefile_fixed():
    makefile_path = '/home/user/release_prep/Makefile'
    assert os.path.isfile(makefile_path), f'File {makefile_path} is missing.'
    with open(makefile_path) as f:
        content = f.read()
    assert '-pthread' in content, 'The Makefile is missing the -pthread flag.'

    lines = content.splitlines()
    run_tests_cmd = ''
    for i, line in enumerate(lines):
        if line.startswith('run_tests:'):
            if i + 1 < len(lines):
                run_tests_cmd = lines[i + 1]
            break
    assert 'src/config_parser.o' in run_tests_cmd or 'config_parser.o' in run_tests_cmd, \
        'The Makefile does not correctly link config_parser.o for the run_tests target.'


def test_cpp_bugs_fixed():
    config_parser_path = '/home/user/release_prep/src/config_parser.cpp'
    assert os.path.isfile(config_parser_path), f'File {config_parser_path} is missing.'
    with open(config_parser_path) as f:
        config_content = f.read()
    assert '"service_port"' not in config_content, \
        "The JSON deserialization bug in config_parser.cpp (looking for 'service_port') was not fixed."
    assert '"port"' in config_content, "config_parser.cpp should look for the correct key 'port'."

    main_path = '/home/user/release_prep/src/main.cpp'
    assert os.path.isfile(main_path), f'File {main_path} is missing.'
    with open(main_path) as f:
        main_content = f.read()
    assert 'const std::string& getStatusMessage()' not in main_content, \
        'The lifetime bug in main.cpp (returning a dangling reference) was not fixed.'
    assert 'std::string getStatusMessage()' in main_content, \
        'getStatusMessage() in main.cpp should return std::string by value.'


def test_test_results_log():
    log_path = '/home/user/test_results.log'
    assert os.path.isfile(log_path), f'The test results log {log_path} is missing.'
    with open(log_path) as f:
        content = f.read().strip()
    assert 'TESTS PASSED' in content, 'The test_results.log does not indicate that the tests passed.'


def test_deploy_ready_txt():
    deploy_path = '/home/user/deploy_ready.txt'
    assert os.path.isfile(deploy_path), f'The deployment ready file {deploy_path} is missing.'
    with open(deploy_path) as f:
        content = f.read().strip()
    try:
        data = json.loads(content)
        assert data.get('status') == 'ok', "The deploy_ready.txt JSON does not have 'status': 'ok'."
        assert data.get('version') == '1.2.0', "The deploy_ready.txt JSON does not have 'version': '1.2.0'."
    except json.JSONDecodeError:
        pytest.fail(f'The file {deploy_path} does not contain valid JSON. Content: {content}')


def test_api_server_running_and_serving():
    try:
        data = json.loads(fetch('http://127.0.0.1:9000/').decode('utf-8'))
        assert data.get('status') == 'ok'
    except Exception as exc:
        pytest.fail(f'Could not connect to the api_server on 127.0.0.1:9000 or it returned invalid data. Error: {exc}')


def test_haproxy_running_and_proxying():
    try:
        data = json.loads(fetch('http://127.0.0.1:8080/status').decode('utf-8'))
        assert data.get('status') == 'ok'
    except Exception as exc:
        pytest.fail(f'Could not connect to HAProxy on 127.0.0.1:8080 or it did not proxy correctly. Error: {exc}')


def test_background_processes_running():
    try:
        ps_output = subprocess.check_output(['ps', 'aux']).decode('utf-8')
        assert 'api_server' in ps_output, 'api_server is not running in the background.'
        assert 'haproxy' in ps_output, 'haproxy is not running in the background.'
    except Exception as exc:
        pytest.fail(f'Failed to check running processes: {exc}')


def test_clean_build_tests_and_real_deployment():
    # Remove pre-existing listeners so substitute servers cannot satisfy the checks below.
    stop_listeners(8080, 9000)

    clean = subprocess.run(['make', 'clean'], cwd=REPO, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert clean.returncode == 0, f'make clean failed:\n{clean.stdout}'
    build = subprocess.run(['make', 'all'], cwd=REPO, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    assert build.returncode == 0, f'make all failed:\n{build.stdout}'

    api_path = os.path.join(REPO, 'api_server')
    tests_path = os.path.join(REPO, 'run_tests')
    for path in (api_path, tests_path):
        assert os.path.isfile(path) and os.access(path, os.X_OK), f'{path} was not built as an executable.'
        with open(path, 'rb') as artifact:
            assert artifact.read(4) == b'\x7fELF', f'{path} is not a compiled ELF executable.'

    result = subprocess.run([tests_path], cwd=REPO, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert result.returncode == 0, f'./run_tests failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    assert 'TESTS PASSED' in result.stdout, './run_tests did not report TESTS PASSED.'
    with open('/home/user/test_results.log') as f:
        recorded = f.read()
    assert recorded == result.stdout, 'test_results.log is not the actual standard output of ./run_tests.'

    # Exercise the submitted parser implementation independently of the submitted test runner.
    with tempfile.TemporaryDirectory() as td:
        harness = os.path.join(td, 'parser_check.cpp')
        binary = os.path.join(td, 'parser_check')
        with open(harness, 'w') as f:
            f.write(r'''#include "config_parser.h"
int main() {
    ConfigParser parser;
    return parser.parsePort("{\"port\": 9000}") == 9000 ? 0 : 1;
}
''')
        compile_check = subprocess.run([
            'g++', '-std=c++14', '-pthread', '-I' + os.path.join(REPO, 'src'),
            harness, os.path.join(REPO, 'src/config_parser.cpp'), '-o', binary
        ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        assert compile_check.returncode == 0, f'Independent config_parser build failed:\n{compile_check.stdout}'
        parser_check = subprocess.run([binary], timeout=5)
        assert parser_check.returncode == 0, 'ConfigParser did not parse the required port fixture.'

    cfg = '/home/user/haproxy.cfg'
    assert os.path.isfile(cfg), 'The HAProxy configuration is missing.'
    haproxy = shutil.which('haproxy')
    assert haproxy, 'haproxy is unavailable.'
    cfg_check = subprocess.run([haproxy, '-c', '-f', cfg], text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    assert cfg_check.returncode == 0, f'Invalid HAProxy configuration:\n{cfg_check.stdout}'
    with open(cfg) as f:
        cfg_text = f.read()
    assert '127.0.0.1:8080' in cfg_text, 'HAProxy is not configured to listen on 127.0.0.1:8080.'
    assert '127.0.0.1:9000' in cfg_text, 'HAProxy is not configured with the API server at 127.0.0.1:9000.'

    api_proc = subprocess.Popen([api_path], cwd=REPO, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    direct_body, direct_data = wait_for_json('http://127.0.0.1:9000/status')
    assert direct_data == EXPECTED, f'Built api_server returned unexpected data: {direct_data}'
    assert_listener_executable(9000, api_path)

    subprocess.Popen([haproxy, '-f', cfg], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    proxy_body, proxy_data = wait_for_json('http://127.0.0.1:8080/status')
    assert proxy_data == EXPECTED, f'HAProxy returned unexpected data: {proxy_data}'
    assert_listener_executable(8080, haproxy)

    # A proxy that fabricates the known JSON must not pass: its response must depend on the API backend.
    api_proc.terminate()
    try:
        api_proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        api_proc.kill()
        api_proc.wait(timeout=2)
    time.sleep(0.5)
    try:
        unavailable_body = fetch('http://127.0.0.1:8080/status', timeout=2)
        assert json.loads(unavailable_body.decode('utf-8')) != EXPECTED, \
            'The proxy still fabricated a successful response while api_server was stopped.'
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError):
        pass

    api_proc = subprocess.Popen([api_path], cwd=REPO, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    final_body, final_data = wait_for_json('http://127.0.0.1:8080/status')
    assert final_data == EXPECTED
    assert_listener_executable(9000, api_path)
    assert_listener_executable(8080, haproxy)

    with open('/home/user/deploy_ready.txt', 'rb') as f:
        saved = f.read()
    assert saved == final_body, 'deploy_ready.txt is not the exact response served through HAProxy.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
