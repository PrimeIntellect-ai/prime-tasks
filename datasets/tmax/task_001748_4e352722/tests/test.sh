#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import stat
import string
import subprocess
import time

import pytest
import requests

APP = '/app/fast-csv-api'
URL = 'http://127.0.0.1:8080/process'


def _random_token(min_len=5, max_len=18):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(max_len - min_len + 1) + min_len))


def _run_processor(payload, timeout=1.5):
    encoded = base64.b64encode(payload.encode('utf-8')).decode('ascii')
    runner = r'''
import base64, json, sys
sys.path.insert(0, '/app/fast-csv-api')
try:
    import processor
    if not callable(getattr(processor, 'process_data', None)):
        raise TypeError('processor.process_data is not callable')
    value = processor.process_data(base64.b64decode(sys.argv[1]).decode('utf-8'))
    print('__RESULT__' + json.dumps({'kind': 'ok', 'value': value}))
except BaseException as exc:
    print('__RESULT__' + json.dumps({'kind': 'error', 'type': type(exc).__name__}))
'''
    started = time.perf_counter()
    try:
        completed = subprocess.run(
            ['python3', '-I', '-c', runner, encoded],
            cwd=APP,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('processor.process_data hung on a generated input with an unclosed quote')

    elapsed = time.perf_counter() - started
    marker_lines = [line for line in completed.stdout.splitlines() if line.startswith('__RESULT__')]
    assert marker_lines, (
        'Could not execute processor.process_data successfully. '
        f'stdout={completed.stdout!r}, stderr={completed.stderr!r}'
    )
    return json.loads(marker_lines[-1][len('__RESULT__'):]), elapsed


def test_required_artifacts_are_regular_files():
    for path in (os.path.join(APP, 'processor.py'), os.path.join(APP, 'server.py')):
        assert os.path.exists(path), f'Required artifact {path} does not exist.'
        mode = os.lstat(path).st_mode
        assert stat.S_ISREG(mode), f'Required artifact {path} is not a regular file.'


def test_poison_pill_contents():
    pill_path = '/home/user/poison_pill.txt'
    assert os.path.isfile(pill_path), f'File {pill_path} does not exist.'

    with open(pill_path, 'r') as f:
        poison_pill = f.read().strip()

    assert poison_pill == '3,"charlie,300', f'Poison pill content is incorrect. Expected \'3,"charlie,300\', got {poison_pill!r}'


def test_processor_preserves_valid_processing_behavior():
    row_count = 3 + secrets.randbelow(6)
    lines = [','.join((_random_token(), _random_token(), str(secrets.randbelow(1000000)))) for _ in range(row_count)]
    payload = '\n'.join(lines)
    expected = [line.split(',') for line in lines]

    result, elapsed = _run_processor(payload)
    assert result['kind'] == 'ok', f'Valid input unexpectedly raised {result}'
    assert result['value'] == expected, f'Valid processing result was incorrect: {result["value"]!r}'
    assert elapsed < 1.0, f'Valid processing took too long ({elapsed:.2f}s)'


def test_processor_terminates_on_generated_unclosed_quotes():
    # These payloads are generated after the agent has finished, rather than being
    # a fixed copy of the known poison pill.
    for _ in range(5):
        fields = [_random_token(), _random_token(), _random_token()]
        bad_field = secrets.randbelow(len(fields))
        insert_at = secrets.randbelow(len(fields[bad_field]) + 1)
        fields[bad_field] = fields[bad_field][:insert_at] + '"' + fields[bad_field][insert_at:]
        malformed = ','.join(fields)

        # Graceful handling may either return a value or raise an error; it may not hang.
        result, elapsed = _run_processor(malformed)
        assert result['kind'] in ('ok', 'error')
        assert elapsed < 1.0, f'Generated malformed input took too long ({elapsed:.2f}s)'


def test_server_processes_poison_pill_without_hanging():
    pill_path = '/home/user/poison_pill.txt'

    if os.path.isfile(pill_path):
        with open(pill_path, 'r') as f:
            poison_pill = f.read().strip()
    else:
        poison_pill = '3,"charlie,300'

    if not poison_pill:
        poison_pill = '3,"charlie,300'

    start_time = time.time()
    try:
        resp = requests.post(URL, data=poison_pill, timeout=2)
        elapsed = time.time() - start_time

        assert resp.status_code == 200, f'Expected HTTP 200, but got {resp.status_code}. Response: {resp.text}'
        assert elapsed < 1.0, f'Request took too long ({elapsed:.2f}s). The infinite loop might not be fixed.'
    except requests.exceptions.Timeout:
        pytest.fail('Server timed out. The infinite loop bug is likely not fixed.')
    except requests.exceptions.ConnectionError:
        pytest.fail('Failed to connect to the server at 127.0.0.1:8080. Is it running?')


def test_server_processes_generated_valid_payload_with_derived_answer():
    row_count = 2 + secrets.randbelow(8)
    lines = [','.join((_random_token(), _random_token(), str(secrets.randbelow(1000000)))) for _ in range(row_count)]
    payload = '\n'.join(lines)

    started = time.perf_counter()
    try:
        resp = requests.post(URL, data=payload, timeout=2)
    except requests.exceptions.Timeout:
        pytest.fail('Server timed out on a generated valid payload.')
    except requests.exceptions.ConnectionError:
        pytest.fail('Failed to connect to the server at 127.0.0.1:8080. Is it running?')
    elapsed = time.perf_counter() - started

    assert resp.status_code == 200, f'Expected HTTP 200 for valid input, got {resp.status_code}: {resp.text}'
    assert elapsed < 1.0, f'Generated valid request took too long ({elapsed:.2f}s)'
    try:
        body = resp.json()
    except ValueError:
        pytest.fail(f'Server did not return its expected JSON response: {resp.text!r}')
    assert body.get('status') == 'success', f'Unexpected response body: {body!r}'
    assert body.get('rows') == row_count, f'Expected {row_count} processed rows, got {body!r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
