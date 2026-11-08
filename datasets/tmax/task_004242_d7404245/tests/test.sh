#!/bin/bash
set +e
mkdir -p /logs/verifier

# Stop any process left listening on port 8080 so the submitted server.py itself
# must successfully start and serve the verification requests.
python3 - <<'PY'
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit() or int(name) in (1, os.getpid(), os.getppid()):
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
PY

cd /home/user/scheduler_service || true
python3 -u /home/user/scheduler_service/server.py > /tmp/scheduler_server.log 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    pkill -TERM -P "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Give the submitted server a bounded period in which to bind and initialize.
python3 - <<'PY'
import sys
import time
import requests

for _ in range(60):
    try:
        requests.post('http://127.0.0.1:8080/allocate', json={'jobs': []}, timeout=0.25)
        sys.exit(0)
    except requests.RequestException:
        time.sleep(0.25)
sys.exit(1)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.machinery
import json
import os
import sys

import requests

PROJECT = '/home/user/scheduler_service'
URL = 'http://127.0.0.1:8080/allocate'


def test_result_json_exists():
    result_path = '/home/user/scheduler_service/result.json'
    assert os.path.exists(result_path), f"{result_path} does not exist. The task was not completed properly."


def test_result_json_content():
    result_path = '/home/user/scheduler_service/result.json'
    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{result_path} does not contain valid JSON."

    assert 'scheduled_jobs' in data, "The key 'scheduled_jobs' is missing from the JSON result."
    assert 'hash' in data, "The key 'hash' is missing from the JSON result."

    expected_jobs = ["J2", "J3", "J5"]
    assert data['scheduled_jobs'] == expected_jobs, f"Expected scheduled_jobs to be {expected_jobs}, but got {data['scheduled_jobs']}"

    expected_hash = sum(sum(ord(c) for c in job_id) for job_id in expected_jobs)
    assert data['hash'] == expected_hash, f"Expected hash to be {expected_hash}, but got {data['hash']}"


def test_server_py_exists():
    server_path = '/home/user/scheduler_service/server.py'
    assert os.path.exists(server_path), f"{server_path} does not exist. The API server script is missing."


def test_c_extension_fixed():
    c_file_path = '/home/user/scheduler_service/job_hasher.c'
    assert os.path.exists(c_file_path), f"{c_file_path} does not exist."
    with open(c_file_path, 'r') as f:
        content = f.read()

    assert "PyBytes_AsString" not in content, "The C-extension still contains PyBytes_AsString, which causes segfaults in Python 3."
    assert "PyUnicode_AsUTF8" in content or "PyUnicode_AsUTF8AndSize" in content, "The C-extension does not seem to use a valid Python 3 Unicode C-API function (like PyUnicode_AsUTF8)."


def test_native_extension_is_built_importable_and_operational():
    sys.path.insert(0, PROJECT)
    sys.modules.pop('job_hasher', None)
    module = importlib.import_module('job_hasher')
    module_path = os.path.realpath(module.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f'job_hasher was not imported as a compiled native extension: {module_path}'

    ids = ['Alpha', 'Z9', 'unicode-object']
    expected = sum(ord(ch) for job_id in ids for ch in job_id)
    assert module.hash_jobs(ids) == expected
    assert module.hash_jobs([]) == 0


def expected_allocation(jobs):
    scheduled = []
    last_end = None
    for job in sorted(jobs, key=lambda item: item['end']):
        if last_end is None or job['start'] >= last_end:
            scheduled.append(job['id'])
            last_end = job['end']
    return {
        'scheduled_jobs': scheduled,
        'hash': sum(ord(ch) for job_id in scheduled for ch in job_id),
    }


def call_allocate(jobs):
    response = requests.post(URL, json={'jobs': jobs}, timeout=3)
    assert response.status_code == 200, response.text
    assert 'application/json' in response.headers.get('Content-Type', '')
    data = response.json()
    assert set(data) == {'scheduled_jobs', 'hash'}
    return data


def test_live_api_on_additional_derived_inputs():
    cases = [
        [],
        [
            {'id': 'LONG', 'start': 0, 'end': 20},
            {'id': 'A7', 'start': 1, 'end': 2},
            {'id': 'B2', 'start': 2, 'end': 3},
            {'id': 'LATE', 'start': 3, 'end': 10},
            {'id': 'C9', 'start': 4, 'end': 5},
        ],
        [
            {'id': 'Q', 'start': 8, 'end': 11},
            {'id': 'N1', 'start': -5, 'end': -2},
            {'id': 'N2', 'start': -2, 'end': 0},
            {'id': 'MIDDLE', 'start': -1, 'end': 8},
            {'id': 'P', 'start': 0, 'end': 4},
            {'id': 'R3', 'start': 4, 'end': 7},
        ],
        [
            {'id': 'x10', 'start': 10, 'end': 12},
            {'id': 'x0', 'start': 0, 'end': 1},
            {'id': 'x4', 'start': 4, 'end': 6},
            {'id': 'block', 'start': 0, 'end': 30},
            {'id': 'x1', 'start': 1, 'end': 4},
            {'id': 'x6', 'start': 6, 'end': 9},
        ],
    ]
    for jobs in cases:
        assert call_allocate(jobs) == expected_allocation(jobs)


def test_saved_result_matches_live_api_for_required_payload():
    jobs = [
        {'id': 'J1', 'start': 0, 'end': 6},
        {'id': 'J2', 'start': 1, 'end': 4},
        {'id': 'J3', 'start': 5, 'end': 7},
        {'id': 'J4', 'start': 4, 'end': 8},
        {'id': 'J5', 'start': 8, 'end': 10},
    ]
    live_data = call_allocate(jobs)
    with open(os.path.join(PROJECT, 'result.json')) as f:
        saved_data = json.load(f)
    assert saved_data == live_data == expected_allocation(jobs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
