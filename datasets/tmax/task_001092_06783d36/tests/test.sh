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
import os
import sys
import time
import csv
import random
import secrets
import tempfile
import requests
import redis
import subprocess
import pytest


def make_generated_corpus(root):
    rng = random.SystemRandom()
    cases = []

    def write_case(rows, expected):
        path = os.path.join(root, secrets.token_hex(12) + '.csv')
        with open(path, 'w', newline='') as f:
            csv.writer(f, lineterminator='\n').writerows(rows)
        cases.append((path, expected))

    # Valid integer matrices with unpredictable names, dimensions, and values.
    for _ in range(5):
        cols = rng.randint(2, 6)
        row_count = rng.randint(2, 7)
        header = ['c_' + secrets.token_hex(4) for _ in range(cols)]
        data = [[rng.randint(-1000000, 1000000) for _ in range(cols)] for _ in range(row_count)]
        write_case([header] + data, True)

    # Otherwise-numeric matrices containing an implicit missing value.
    for _ in range(3):
        cols = rng.randint(2, 6)
        row_count = rng.randint(2, 7)
        header = ['c_' + secrets.token_hex(4) for _ in range(cols)]
        data = [[str(rng.randint(-1000000, 1000000)) for _ in range(cols)] for _ in range(row_count)]
        data[rng.randrange(row_count)][rng.randrange(cols)] = ''
        write_case([header] + data, False)

    # Integer-valued data already represented as floats must also be rejected.
    for _ in range(3):
        cols = rng.randint(2, 6)
        row_count = rng.randint(2, 7)
        header = ['c_' + secrets.token_hex(4) for _ in range(cols)]
        data = [[f'{rng.randint(-1000000, 1000000)}.0' for _ in range(cols)] for _ in range(row_count)]
        write_case([header] + data, False)

    # Include a non-integral float in an otherwise count-like numeric matrix.
    for _ in range(2):
        cols = rng.randint(2, 6)
        row_count = rng.randint(2, 7)
        header = ['c_' + secrets.token_hex(4) for _ in range(cols)]
        data = [[str(rng.randint(-1000000, 1000000)) for _ in range(cols)] for _ in range(row_count)]
        r_index = rng.randrange(row_count)
        c_index = rng.randrange(cols)
        data[r_index][c_index] = f'{rng.randint(1, 999999)}.5'
        write_case([header] + data, False)

    rng.shuffle(cases)
    return cases


def load_sanitizer():
    sanitizer_path = '/home/user/app/sanitizer.py'
    assert os.path.isfile(sanitizer_path), 'sanitizer.py is missing from /home/user/app'
    sys.path.insert(0, '/home/user/app')
    try:
        import sanitizer
    except ImportError:
        pytest.fail('Failed to import sanitizer.py from /home/user/app')
    assert hasattr(sanitizer, 'validate_dataset'), 'sanitizer.py is missing validate_dataset function'
    assert callable(sanitizer.validate_dataset), 'validate_dataset is not callable'
    return sanitizer


def test_sanitizer_adversarial_corpus():
    sanitizer = load_sanitizer()

    evil_dir = '/home/user/eval_corpus/evil'
    clean_dir = '/home/user/eval_corpus/clean'

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]

    evil_bypassed = []
    for f in evil_files:
        try:
            res = sanitizer.validate_dataset(f)
            if res is not False:
                evil_bypassed.append(os.path.basename(f))
        except Exception:
            pass

    clean_rejected = []
    for f in clean_files:
        try:
            res = sanitizer.validate_dataset(f)
            if res is not True:
                clean_rejected.append(os.path.basename(f))
        except Exception:
            clean_rejected.append(os.path.basename(f))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_msg.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    if error_msg:
        pytest.fail(' | '.join(error_msg))


def test_sanitizer_generated_cases():
    sanitizer = load_sanitizer()
    with tempfile.TemporaryDirectory(prefix='dataset-check-') as root:
        cases = make_generated_corpus(root)
        for path, expected in cases:
            try:
                actual = sanitizer.validate_dataset(path)
            except Exception as exc:
                pytest.fail(f'validate_dataset raised {type(exc).__name__} on a generated case')
            assert actual is expected, f'validate_dataset returned {actual!r}; expected {expected!r} for generated CSV data'


def test_integration_and_services():
    subprocess.run(['pkill', '-f', 'redis-server'], capture_output=True)
    subprocess.run(['pkill', '-f', 'gunicorn'], capture_output=True)
    subprocess.run(['pkill', '-f', 'nginx'], capture_output=True)

    start_script = '/home/user/app/start_services.sh'
    assert os.path.isfile(start_script), 'start_services.sh is missing'

    subprocess.Popen([start_script], cwd='/home/user/app')
    time.sleep(3)

    r = redis.Redis(host='localhost', port=6379, db=0)
    try:
        r.ping()
    except redis.ConnectionError:
        pytest.fail('Redis is not running on port 6379')

    r.delete('dataset_queue')

    clean_file = '/home/user/eval_corpus/clean/data1.csv'
    evil_file = '/home/user/eval_corpus/evil/data1.csv'

    try:
        with open(clean_file, 'rb') as f:
            resp = requests.post('http://localhost:8080/upload', files={'file': f}, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail('Nginx is not listening on port 8080 or failed to proxy to Flask')

    assert resp.status_code == 200, f'Expected HTTP 200 for clean file, got {resp.status_code}'

    queue_len = r.llen('dataset_queue')
    assert queue_len == 1, f'Expected 1 item in Redis dataset_queue, got {queue_len}'

    with open(evil_file, 'rb') as f:
        resp = requests.post('http://localhost:8080/upload', files={'file': f}, timeout=5)

    assert resp.status_code == 400, f'Expected HTTP 400 for evil file, got {resp.status_code}'

    queue_len = r.llen('dataset_queue')
    assert queue_len == 1, f'Expected still 1 item in Redis dataset_queue, got {queue_len} (evil file bypassed queue check)'

    # Exercise the full proxy/API/Redis path with unpredictable paths and data.
    expected_queue_len = 1
    with tempfile.TemporaryDirectory(prefix='upload-check-') as root:
        for path, expected_clean in make_generated_corpus(root):
            with open(path, 'rb') as f:
                raw = f.read()
            with open(path, 'rb') as f:
                resp = requests.post(
                    'http://localhost:8080/upload',
                    files={'file': (os.path.basename(path), f, 'text/csv')},
                    timeout=5,
                )

            if expected_clean:
                assert resp.status_code == 200, f'Expected HTTP 200 for generated clean CSV, got {resp.status_code}'
                expected_queue_len += 1
                assert r.llen('dataset_queue') == expected_queue_len, 'Clean upload was not added exactly once to dataset_queue'
                assert r.lindex('dataset_queue', 0) == raw, 'Queued clean dataset does not match the uploaded raw text'
            else:
                assert resp.status_code == 400, f'Expected HTTP 400 for generated corrupted CSV, got {resp.status_code}'
                assert r.llen('dataset_queue') == expected_queue_len, 'Rejected dataset changed dataset_queue'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
