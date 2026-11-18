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
import calendar
import datetime
import os
import random
import stat
from pathlib import Path

import pytest
import requests

REPO = Path('/app/timeserver_repo')
BINARY = REPO / 'timeserver'
SOURCE = REPO / 'server.c'
URL = 'http://127.0.0.1:9090/convert'


def _listener_inodes(address='0100007F', port=9090):
    wanted = f'{address}:{port:04X}'
    inodes = set()
    with open('/proc/net/tcp', encoding='ascii') as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])
    return inodes


def _listener_pids(inodes):
    pids = set()
    for entry in os.scandir('/proc'):
        if not entry.name.isdigit():
            continue
        fd_dir = f'/proc/{entry.name}/fd'
        try:
            for fd in os.scandir(fd_dir):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(entry.name))
        except OSError:
            continue
    return pids


def _request(datetime_string):
    try:
        return requests.get(URL, params={'datetime': datetime_string}, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail('The timeserver is not running or not listening on 127.0.0.1:9090.')
    except requests.exceptions.Timeout:
        pytest.fail(f'The timeserver timed out for {datetime_string!r}.')


def test_compiled_repository_artifact_is_the_running_server():
    assert SOURCE.is_file(), f'Missing required source file: {SOURCE}'
    assert BINARY.is_file(), f'Missing compiled executable: {BINARY}'
    mode = BINARY.stat().st_mode
    assert stat.S_ISREG(mode) and os.access(BINARY, os.X_OK), 'timeserver is not an executable regular file'
    with BINARY.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'timeserver must be a compiled native executable'
    assert BINARY.stat().st_mtime_ns >= SOURCE.stat().st_mtime_ns, 'timeserver was not rebuilt after server.c was changed'

    inodes = _listener_inodes()
    assert inodes, 'No process is listening specifically on 127.0.0.1:9090'
    pids = _listener_pids(inodes)
    assert pids, 'Could not identify the process listening on 127.0.0.1:9090'
    assert any(
        os.path.exists(f'/proc/{pid}/exe') and os.path.samefile(f'/proc/{pid}/exe', BINARY)
        for pid in pids
    ), 'The listener on 127.0.0.1:9090 is not the compiled timeserver artifact'


def test_timeserver_port_and_bug_ticket_fix():
    response = _request('2023-10-29T01:30:00-CET')
    assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
    assert response.text.strip() == '1698543000', f"Expected body '1698543000', got {response.text!r}"


def test_timeserver_utc_conversion():
    response = _request('2024-01-01T12:00:00-UTC')
    assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
    assert response.text.strip() == '1704110400', f"Expected body '1704110400', got {response.text!r}"


def test_general_utc_conversion_on_unpredictable_inputs():
    rng = random.SystemRandom()
    lower = calendar.timegm((2001, 1, 1, 0, 0, 0))
    upper = calendar.timegm((2035, 12, 31, 23, 59, 59))
    cases = set()
    while len(cases) < 10:
        epoch = rng.randrange(lower, upper + 1)
        dt = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
        value = dt.strftime('%Y-%m-%dT%H:%M:%S-UTC')
        if value != '2024-01-01T12:00:00-UTC':
            cases.add((value, calendar.timegm(dt.utctimetuple())))

    for value, expected in cases:
        response = _request(value)
        assert response.status_code == 200, f'Expected HTTP 200 for {value}, got {response.status_code}'
        assert response.text.strip() == str(expected), (
            f'Expected {expected} for {value}, got {response.text!r}'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
