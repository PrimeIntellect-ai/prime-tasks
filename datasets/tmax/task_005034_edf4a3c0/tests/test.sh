#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import re
import socket
import subprocess
import time

import pytest
import redis
import requests

URL = 'http://127.0.0.1:5000/telemetry'
FILTER = '/home/user/telemetry_filter.py'


def test_service_is_running():
    """Verify that the Flask receiver is listening on port 5000."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(('127.0.0.1', 5000))
        assert result == 0, "The Telemetry Receiver service is not listening on port 5000. Did you start the services?"


def test_adversarial_corpus_filtering():
    """Verify that the filter strictly accepts clean payloads and rejects evil payloads."""
    clean_files = glob.glob('/app/corpora/clean/*.json')
    evil_files = glob.glob('/app/corpora/evil/*.json')

    assert len(clean_files) > 0, "No clean payload files found in /app/corpora/clean/"
    assert len(evil_files) > 0, "No evil payload files found in /app/corpora/evil/"

    clean_failed = []
    for f in clean_files:
        with open(f, 'r') as file:
            data = json.load(file)
        try:
            res = requests.post(URL, json=data, timeout=2)
            if res.status_code != 200:
                clean_failed.append(os.path.basename(f))
        except Exception:
            clean_failed.append(os.path.basename(f))

    evil_bypassed = []
    for f in evil_files:
        with open(f, 'r') as file:
            data = json.load(file)
        try:
            res = requests.post(URL, json=data, timeout=2)
            if res.status_code == 200:
                evil_bypassed.append(os.path.basename(f))
        except Exception:
            pass

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_filter_script_exists_and_executable():
    """Verify that the telemetry filter script exists and is executable."""
    assert os.path.isfile(FILTER), f"Filter script {FILTER} is missing."
    assert os.access(FILTER, os.X_OK), f"Filter script {FILTER} is not executable."


def strict_valid(obj):
    if not isinstance(obj, dict) or set(obj) != {'device_id', 'timestamp', 'metrics'}:
        return False
    if not isinstance(obj['device_id'], str) or re.fullmatch(r'DEV-\d{4}', obj['device_id']) is None:
        return False
    if not isinstance(obj['timestamp'], int) or isinstance(obj['timestamp'], bool):
        return False
    metrics = obj['metrics']
    if not isinstance(metrics, dict):
        return False
    for key, value in metrics.items():
        if not isinstance(key, str):
            return False
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            return False
    if 'temperature' in metrics and not (-50.0 <= metrics['temperature'] <= 100.0):
        return False
    return True


def make_payload(rng, index):
    base = {
        'device_id': f'DEV-{rng.randrange(10000):04d}',
        'timestamp': 2000000000 + index * 1000 + rng.randrange(1000),
        'metrics': {
            'temperature': round(rng.uniform(-50, 100), 4),
            'humidity': round(rng.uniform(0, 100), 4),
            f'sensor_{rng.randrange(100000)}': rng.randrange(-100000, 100001),
        },
    }
    kind = rng.randrange(13)
    if kind in (0, 1, 2):
        if kind == 1:
            base['metrics'].pop('temperature')
        elif kind == 2:
            base['metrics'] = {}
        return base
    if kind == 3:
        base['debug'] = rng.randrange(1000000)
    elif kind == 4:
        base.pop(rng.choice(list(base.keys())))
    elif kind == 5:
        base['device_id'] = rng.choice(['DEV-123', 'DEV-12345', 'dev-1234', 'DEV-12A4', 1234, None])
    elif kind == 6:
        base['timestamp'] = rng.choice([True, False, str(base['timestamp']), 1.25, None])
    elif kind == 7:
        base['metrics'] = rng.choice([[], 'metrics', None, 7])
    elif kind == 8:
        base['metrics']['humidity'] = rng.choice([True, False, '50', None, [], {}])
    elif kind == 9:
        base['metrics']['temperature'] = 100.0001 + rng.random() * 10000
    elif kind == 10:
        base['metrics']['temperature'] = -50.0001 - rng.random() * 10000
    elif kind == 11:
        return rng.choice([[], ['telemetry'], 'payload', 42, True, None])
    else:
        base['device_id'] += 'x'
    return base


def run_filter(raw):
    return subprocess.run([FILTER], input=raw, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=3).returncode


def test_filter_directly_on_derived_random_cases():
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = [make_payload(rng, i) for i in range(120)]
    for obj in cases:
        rc = run_filter(json.dumps(obj, separators=(',', ':')).encode())
        assert (rc == 0) == strict_valid(obj), f"Filter gave wrong result for generated payload: {obj!r}"
    for raw in (b'', b'{', b'not-json', b'{"device_id":', b'[1,2,', b'null'):
        assert run_filter(raw) != 0, f"Filter accepted malformed JSON: {raw!r}"


def proc_info(fragment):
    found = []
    for path in glob.glob('/proc/[0-9]*/cmdline'):
        try:
            raw = open(path, 'rb').read()
            cmd = raw.replace(b'\0', b' ').decode(errors='replace')
            if fragment in cmd and '/tmp/test_final_state.py' not in cmd:
                env_path = path.rsplit('/', 1)[0] + '/environ'
                env = open(env_path, 'rb').read().split(b'\0')
                found.append((cmd, env))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def has_env(entries, value):
    wanted = value.encode()
    return any(wanted in env for _, env in entries)


def test_orchestration_environment_and_live_components():
    path = '/app/start_services.sh'
    assert os.path.isfile(path), 'Missing /app/start_services.sh'
    assert os.access(path, os.X_OK), '/app/start_services.sh is not executable'
    subprocess.run(['/bin/bash', '-n', path], check=True, timeout=3)

    raw_lines = open(path, encoding='utf-8').read().splitlines()
    lines = [line.split('#', 1)[0].strip().lower() for line in raw_lines]
    redis_lines = [i for i, line in enumerate(lines) if 'redis-server' in line]
    receiver_lines = [i for i, line in enumerate(lines) if 'receiver.py' in line]
    worker_lines = [i for i, line in enumerate(lines) if 'worker.py' in line]
    assert redis_lines and receiver_lines and worker_lines, 'Startup script must launch Redis, receiver.py, and worker.py'
    first_app = min(receiver_lines[0], worker_lines[0])
    loops = [i for i, line in enumerate(lines) if re.search(r'\b(while|until)\b', line)]
    assert loops, 'Startup script does not wait in a readiness loop for Redis'
    wait_line = next((i for i in loops if redis_lines[0] < i < first_app), None)
    assert wait_line is not None, 'Redis readiness loop must run after Redis starts and before receiver/worker launch'
    readiness = '\n'.join(lines[wait_line:first_app])
    assert ('6379' in readiness or 'redis-cli' in readiness) and any(
        token in readiness for token in ('redis-cli', 'nc ', 'netcat', '/dev/tcp', 'ss ', 'lsof')
    ), 'Readiness loop must actively test Redis TCP port 6379 before launching applications'
    assert redis_lines[0] < receiver_lines[0] and redis_lines[0] < worker_lines[0]

    broker = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=2)
    assert broker.ping() is True, 'Redis is not responding on TCP port 6379'
    assert proc_info('redis-server'), 'No redis-server process is running'
    receivers = proc_info('/app/receiver.py')
    workers = proc_info('/app/worker.py')
    assert receivers, 'The real /app/receiver.py process is not running'
    assert workers, 'The real /app/worker.py process is not running'
    assert has_env(receivers, 'REDIS_URL=redis://127.0.0.1:6379/0'), 'Receiver lacks the required REDIS_URL export'
    assert has_env(receivers, 'FILTER_SCRIPT=/home/user/telemetry_filter.py'), 'Receiver lacks the required FILTER_SCRIPT export'
    assert has_env(workers, 'REDIS_URL=redis://127.0.0.1:6379/0'), 'Worker lacks the required REDIS_URL export'


def test_randomized_http_filtering_and_worker_output():
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    cases = [make_payload(rng, i + 10000) for i in range(220)]
    expected = [(obj, strict_valid(obj)) for obj in cases]
    assert any(ok for _, ok in expected) and any(not ok for _, ok in expected)

    broker = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=2)
    broker.delete('telemetry_queue')
    os.makedirs('/app', exist_ok=True)
    if not os.path.exists('/app/output.log'):
        open('/app/output.log', 'a').close()
    start = os.path.getsize('/app/output.log')

    for obj, should_accept in expected:
        response = requests.post(URL, json=obj, timeout=3)
        if should_accept:
            assert response.status_code == 200, f"Valid generated payload was rejected with {response.status_code}: {obj!r}"
        else:
            assert response.status_code != 200, f"Invalid generated payload was accepted: {obj!r}"

    valid_lines = ['Processed: ' + json.dumps(obj) + '\n' for obj, ok in expected if ok]
    invalid_lines = ['Processed: ' + json.dumps(obj) + '\n' for obj, ok in expected if not ok]
    deadline = time.time() + 15
    new_output = ''
    while time.time() < deadline:
        with open('/app/output.log', encoding='utf-8', errors='replace') as handle:
            handle.seek(start)
            new_output = handle.read()
        if all(line in new_output for line in valid_lines):
            break
        time.sleep(0.1)

    missing = [line for line in valid_lines if line not in new_output]
    assert not missing, f"Worker did not process {len(missing)} accepted generated payload(s)"
    leaked = [line for line in invalid_lines if line in new_output]
    assert not leaked, f"Worker processed {len(leaked)} rejected generated payload(s)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
