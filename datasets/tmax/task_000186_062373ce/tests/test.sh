#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import secrets
import subprocess
import time
import uuid

import redis
import requests

API_URL = 'http://127.0.0.1:5000/process'
WORKER_PATH = '/home/user/app/worker.js'


def worker_is_running():
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                argv = [part.decode(errors='replace') for part in f.read().split(b'\0') if part]
            if not argv or not os.path.basename(argv[0]).startswith('node'):
                continue
            cwd = os.readlink(f'/proc/{pid}/cwd')
            for arg in argv[1:]:
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.realpath(candidate) == WORKER_PATH:
                    return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def cyclic_payload(index):
    root_value = secrets.randbelow(900) + 50
    child_value = secrets.randbelow(900) + 50
    root_id = f'root_{index}_{uuid.uuid4().hex}'
    return {
        'id': root_id,
        'value': root_value,
        'children': [{
            'id': f'child_{index}_{uuid.uuid4().hex}',
            'value': child_value,
            'children': [{
                'id': root_id,
                'value': root_value,
                'children': []
            }]
        }]
    }, root_value + child_value


def test_pipeline_performance_and_correctness():
    assert os.path.isfile(WORKER_PATH), f'Missing worker artifact: {WORKER_PATH}'
    syntax = subprocess.run(['node', '--check', WORKER_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, syntax.stderr

    rdb = redis.Redis(host='127.0.0.1', port=6379, db=0)
    assert rdb.ping(), 'Redis is not running on port 6379'
    assert worker_is_running(), 'The Node.js worker.js process is not running'

    # Exercise worker.js independently through its documented Redis queue.
    rdb.delete('job_queue')
    direct_jobs = []
    for i in range(8):
        payload, expected = cyclic_payload(f'direct_{i}')
        job_id = f'verifier_{uuid.uuid4().hex}'
        direct_jobs.append((job_id, expected))
        rdb.lpush('job_queue', json.dumps({'id': job_id, 'payload': payload}))

    deadline = time.monotonic() + 2.0
    pending = dict(direct_jobs)
    while pending and time.monotonic() < deadline:
        for job_id in list(pending):
            raw = rdb.get(f'result_{job_id}')
            if raw is not None:
                actual = json.loads(raw)
                assert actual == pending[job_id], (
                    f'worker.js returned {actual} for {job_id}; expected {pending[job_id]}'
                )
                rdb.delete(f'result_{job_id}')
                del pending[job_id]
        if pending:
            time.sleep(0.005)
    assert not pending, f'worker.js did not process Redis jobs: {list(pending)}'

    # Remove old result keys so API requests can also be tied to Redis processing.
    old_keys = list(rdb.scan_iter(match='result_*'))
    if old_keys:
        rdb.delete(*old_keys)

    jobs = [cyclic_payload(i) for i in range(100)]
    expected_results = []
    start = time.perf_counter()
    for i, (job, expected) in enumerate(jobs):
        response = requests.post(API_URL, json=job, timeout=2.0)
        assert response.status_code == 200, (
            f'Expected status 200 for job {i}, got {response.status_code}. '
            f'Response: {response.text}'
        )
        data = response.json()
        assert isinstance(data, dict), f'Job {i} returned a non-object JSON response'
        assert data.get('status') == 'success', f'Job {i} did not report success: {data}'
        assert 'result' in data, f'Job {i} response omitted result: {data}'
        assert data['result'] == expected, (
            f'Incorrect sum for job {i}: got {data["result"]}, expected {expected}'
        )
        expected_results.append(expected)

    duration = time.perf_counter() - start
    assert duration <= 3.0, (
        f'Pipeline processing too slow. Took {duration:.2f} seconds, expected <= 3.0 seconds.'
    )

    redis_results = []
    for key in rdb.scan_iter(match='result_*'):
        raw = rdb.get(key)
        if raw is not None:
            redis_results.append(json.loads(raw))
    expected_counts = collections.Counter(expected_results)
    actual_counts = collections.Counter(redis_results)
    assert all(actual_counts[value] >= count for value, count in expected_counts.items()), (
        'API requests did not produce the expected results through Redis'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
