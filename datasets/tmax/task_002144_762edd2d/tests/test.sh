#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import signal
import socket
import sqlite3
import subprocess
import time

import pytest
import redis

PAYLOADS_FILE = '/app/data/payloads.jsonl'
DB_FILE = '/app/data/processed.db'
TOKEN = 'sk-ops-99812-secret'


def expected_payloads():
    result = []
    for i in range(1000):
        if i % 100 == 0:
            result.append({
                'id': str(i),
                'message_b64': 'invalid_base64!!!',
                'is_corrupted': True,
            })
        else:
            result.append({
                'id': str(i),
                'message_b64': base64.b64encode(f'Message {i}'.encode()).decode(),
                'is_corrupted': False,
            })
    return result


def read_and_validate_source():
    assert os.path.isfile(PAYLOADS_FILE), f'Payloads file missing at {PAYLOADS_FILE}'

    parsed = []
    total_valid = 0
    try:
        with open(PAYLOADS_FILE, 'r') as f:
            for line in f:
                if not line.strip():
                    continue
                data = json.loads(line)
                parsed.append(data)
                if data.get('is_corrupted') != True:
                    total_valid += 1
    except Exception as e:
        pytest.fail(f'Failed to read or parse payloads file: {e}')

    assert total_valid > 0, 'No valid payloads found in the source file.'
    assert parsed == expected_payloads(), 'The original payload dataset was modified.'
    return total_valid


def wait_for_port(port, process, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f'Service on port {port} exited before becoming ready.')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f'Service on port {port} did not become ready.')


def stop_old_services():
    subprocess.run(['pkill', '-f', '[p]ython3.*app.py'], check=False)
    subprocess.run(['pkill', '-f', '[p]ython3.*processor.py'], check=False)
    subprocess.run(['redis-cli', 'shutdown', 'nosave'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)


def test_recovery_rate():
    total_valid = read_and_validate_source()

    assert os.path.isfile('/app/inject.py'), 'Injection script is missing.'
    assert os.path.isfile('/app/api/app.py'), 'API implementation is missing.'
    assert os.path.isfile('/app/worker/processor.py'), 'Worker implementation is missing.'

    stop_old_services()
    if os.path.exists(DB_FILE):
        os.remove(DB_FILE)

    api = None
    worker = None
    api_log = open('/tmp/verifier_api.log', 'w')
    worker_log = open('/tmp/verifier_worker.log', 'w')
    try:
        subprocess.run(['redis-server', '--daemonize', 'yes'], check=True)
        r = redis.Redis(host='localhost', port=6379, db=0)
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                if r.ping():
                    break
            except Exception:
                time.sleep(0.1)
        else:
            pytest.fail('Redis did not become ready.')
        r.flushall()

        env = os.environ.copy()
        env['API_SECRET_TOKEN'] = TOKEN
        api = subprocess.Popen(
            ['python3', '/app/api/app.py'], cwd='/app/api', env=env,
            stdout=api_log, stderr=subprocess.STDOUT,
        )
        wait_for_port(5000, api)

        worker = subprocess.Popen(
            ['python3', '/app/worker/processor.py'], cwd='/app/worker', env=env,
            stdout=worker_log, stderr=subprocess.STDOUT,
        )

        try:
            injected = subprocess.run(
                ['python3', '/app/inject.py'], cwd='/app', env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, timeout=90,
            )
        except subprocess.TimeoutExpired:
            pytest.fail('The injection script did not finish in time.')
        assert injected.returncode == 0, f'Injection script failed:\n{injected.stdout}'

        deadline = time.time() + 45
        while time.time() < deadline:
            if worker.poll() is not None:
                pytest.fail('Worker crashed while processing the payloads.')
            count = 0
            if os.path.isfile(DB_FILE):
                try:
                    with sqlite3.connect(DB_FILE) as conn:
                        count = conn.execute('SELECT COUNT(*) FROM logs').fetchone()[0]
                except sqlite3.Error:
                    count = 0
            if count >= total_valid and r.llen('log_queue') == 0:
                break
            time.sleep(0.2)

        # Ensure the mutable source was not changed to influence verification.
        assert read_and_validate_source() == total_valid

        processed = 0
        if os.path.isfile(DB_FILE):
            try:
                conn = sqlite3.connect(DB_FILE)
                cursor = conn.cursor()
                cursor.execute('SELECT COUNT(*) FROM logs')
                row = cursor.fetchone()
                if row:
                    processed = row[0]
                cursor.execute('SELECT id, message FROM logs')
                rows = cursor.fetchall()
                conn.close()
            except Exception as e:
                pytest.fail(f'Failed to query the processed database: {e}')
        else:
            pytest.fail(f'Processed database missing at {DB_FILE}. Pipeline did not save data.')

        expected_rows = {
            (str(i), f'Message {i}') for i in range(1000) if i % 100 != 0
        }
        normalized_rows = [(str(record_id), message) for record_id, message in rows]

        assert processed == len(normalized_rows)
        assert len(normalized_rows) == len(set(normalized_rows)), \
            'The database contains duplicate processed records.'
        unexpected = set(normalized_rows) - expected_rows
        assert not unexpected, \
            f'The database contains fabricated, corrupted, or incorrectly decoded rows: {list(unexpected)[:5]}'

        recovery_rate = processed / total_valid
        assert recovery_rate >= 0.98, (
            f'Data recovery rate is too low. '
            f'Processed {processed} out of {total_valid} valid payloads. '
            f'Recovery rate: {recovery_rate:.4f} (Threshold: 0.98)'
        )
    finally:
        for process in (worker, api):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
        api_log.close()
        worker_log.close()
        subprocess.run(['redis-cli', 'shutdown', 'nosave'], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
