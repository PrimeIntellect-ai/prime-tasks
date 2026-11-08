#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import pathlib
import random
import re
import secrets
import signal
import socket
import stat
import string
import subprocess
import time
import zoneinfo

import pytest
import requests

SOURCE = pathlib.Path('/home/user/monitor.c')
INSTALLED = pathlib.Path('/home/user/monitor')
REBUILT = pathlib.Path('/tmp/monitor_rebuilt')
KEYWORD = 'SHIBBOLETH'


def _pids_listening_on_8080():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].endswith(':1F90') and fields[3] == '0A':
                inodes.add(fields[9])

    pids = set()
    for proc in pathlib.Path('/proc').iterdir():
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
                    break
        except OSError:
            continue
    return pids


def _clear_port():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = _pids_listening_on_8080()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)
    assert not _pids_listening_on_8080(), 'Could not stop the previous service on port 8080'


def _wait_for_server(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(('127.0.0.1', 8080)) == 0:
                return
        if proc.poll() is not None and not _pids_listening_on_8080():
            pytest.fail(f'Server exited before listening (exit code {proc.returncode})')
        time.sleep(0.1)
    pytest.fail('Server did not listen on 127.0.0.1:8080 within 5 seconds')


@pytest.fixture(scope='session')
def artifact_validation():
    for path in (SOURCE, INSTALLED):
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError:
            pytest.fail(f'Required artifact is missing: {path}')
        assert stat.S_ISREG(mode), f'Required artifact must be a regular file: {path}'

    assert os.access(INSTALLED, os.X_OK), '/home/user/monitor is not executable'
    assert INSTALLED.read_bytes()[:4] == b'\x7fELF', '/home/user/monitor is not an ELF executable'
    assert SOURCE.stat().st_size > 0, '/home/user/monitor.c is empty'

    result = subprocess.run(
        ['gcc', '-O2', '-pthread', str(SOURCE), '-o', str(REBUILT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'/home/user/monitor.c does not compile as C:\n{result.stderr}'
    assert REBUILT.read_bytes()[:4] == b'\x7fELF'
    return [str(INSTALLED), str(REBUILT)]


def test_required_c_artifacts(artifact_validation):
    assert len(artifact_validation) == 2


@pytest.fixture(params=['installed', 'rebuilt'])
def server(request, artifact_validation):
    executable = artifact_validation[0 if request.param == 'installed' else 1]
    _clear_port()
    proc = subprocess.Popen(
        [executable],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd='/home/user',
    )
    _wait_for_server(proc)
    yield 'http://127.0.0.1:8080'
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)
    _clear_port()


def test_health_endpoint(server):
    """Test the GET /health endpoint for correct status and timezone."""
    try:
        response = requests.get(server + '/health', timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to the service on 127.0.0.1:8080: {e}')

    assert response.status_code == 200, f'Expected status 200, got {response.status_code}'

    body = response.text.strip()
    match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (CET|CEST)', body)
    assert match is not None, f'Response body does not match expected date format and timezone (CET/CEST): {body}'

    time_str = match.group(1)
    try:
        parsed_time = datetime.datetime.strptime(time_str, '%Y-%m-%d %H:%M:%S')
    except ValueError:
        pytest.fail(f'Could not parse time string: {time_str}')

    tz = zoneinfo.ZoneInfo('Europe/Berlin')
    now = datetime.datetime.now(tz).replace(tzinfo=None)
    time_diff = abs((now - parsed_time).total_seconds())
    assert time_diff < 120, f'Returned time {parsed_time} is not within 120 seconds of current Europe/Berlin time {now}'


def test_alert_endpoint_success(server):
    """Test the POST /alert endpoint with the correct keyword."""
    try:
        response = requests.post(server + '/alert', data=KEYWORD, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to the service on 127.0.0.1:8080: {e}')

    assert response.status_code == 202, f'Expected status 202, got {response.status_code}'
    assert 'TRIGGER_MAIL' in response.text, f"Expected 'TRIGGER_MAIL' in response body, got: {response.text}"


@pytest.mark.parametrize('padding', [' ', '  \t', '\r\n', '\t \r\n  '])
def test_alert_ignores_only_edge_whitespace(server, padding):
    response = requests.post(server + '/alert', data=padding + KEYWORD + padding, timeout=5)
    assert response.status_code == 202
    assert 'TRIGGER_MAIL' in response.text


def test_alert_endpoint_failure(server):
    """Retain the original incorrect-keyword assertion."""
    try:
        response = requests.post(server + '/alert', data='WRONG', timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to the service on 127.0.0.1:8080: {e}')

    assert response.status_code == 403, f'Expected status 403, got {response.status_code}'


def test_alert_rejects_random_nonmatching_bodies(server):
    alphabet = string.ascii_letters + string.digits
    nonce = ''.join(secrets.choice(alphabet) for _ in range(24))
    invalid = [
        '',
        KEYWORD.lower(),
        KEYWORD + nonce,
        nonce + KEYWORD,
        KEYWORD[:4] + ' ' + KEYWORD[4:],
        KEYWORD[:-1],
        KEYWORD + KEYWORD,
        nonce,
    ]
    for _ in range(8):
        candidate = ''.join(secrets.choice(alphabet) for _ in range(random.randint(1, 40)))
        if candidate.strip() != KEYWORD:
            invalid.append(candidate)

    for body in invalid:
        assert body.strip() != KEYWORD
        response = requests.post(server + '/alert', data=body, timeout=5)
        assert response.status_code == 403, f'Nonmatching body was accepted: {body!r}'
        assert 'TRIGGER_MAIL' not in response.text
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
