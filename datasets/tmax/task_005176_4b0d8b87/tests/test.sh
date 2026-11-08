#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import glob
import http.client
import os
import secrets
import signal
import subprocess
import tempfile
import time
import uuid

import redis


def test_filter_script_exists_and_executable():
    script_path = '/home/user/filter.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_config_ini_updated():
    config_path = '/home/user/app/config.ini'
    assert os.path.isfile(config_path), f"Config file {config_path} does not exist."

    config = configparser.ConfigParser()
    config.read(config_path)

    assert 'DEFAULT' in config, "DEFAULT section missing in config.ini"
    assert config['DEFAULT'].get('PRE_FILTER_CMD') == '/home/user/filter.sh', "PRE_FILTER_CMD is not updated to /home/user/filter.sh"


def test_adversarial_corpus():
    script_path = '/home/user/filter.sh'
    clean_dir = '/home/user/corpora/clean/'
    evil_dir = '/home/user/corpora/evil/'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    clean_failed = []
    for cf in clean_files:
        result = subprocess.run([script_path, cf], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        result = subprocess.run([script_path, ef], capture_output=True)
        if result.returncode == 0:
            evil_failed.append(os.path.basename(ef))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:10])}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed[:10])}")

    assert not clean_failed and not evil_failed, " | ".join(error_msgs)


def test_filter_on_random_neutral_paths():
    script_path = '/home/user/filter.sh'
    rng = secrets.SystemRandom()
    header = 'id,feature_A,feature_B,target\n'
    cases = []

    for _ in range(12):
        rows = []
        for row_id in range(rng.randint(1, 8)):
            a = rng.uniform(-999.9, 999.9)
            b = rng.uniform(-1000000, 1000000)
            target = rng.choice((0, 1))
            rows.append(f'{row_id},{a:.8f},{b:.8f},{target}')
        cases.append((header + '\n'.join(rows) + '\n', True))

    cases.extend([
        (header + '0,-1000,3,0\n1,1000,-7.5,1\n', True),
        ('id,feature_A,feature_B,wrong\n0,1,2,0\n', False),
        (header + 'not_an_integer,1,2,0\n', False),
        (header + '0,,2,0\n', False),
        (header + '0,abc,2,0\n', False),
        (header + '0,1,,0\n', False),
        (header + '0,1,abc,0\n', False),
        (header + f'0,{1000.01 + rng.random():.8f},2,0\n', False),
        (header + f'0,{-1000.01 - rng.random():.8f},2,0\n', False),
        (header + '0,1,2,2\n', False),
        (header + '0,1,2,\n', False),
        (header + '0,1,2,0,extra\n', False),
        (header + '0,1,0\n', False),
    ])
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix='csv-check-', dir='/tmp') as temp_dir:
        failures = []
        for content, should_accept in cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex + '.dat')
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(content)
            result = subprocess.run([script_path, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            accepted = result.returncode == 0
            if accepted != should_accept:
                failures.append((os.path.basename(path), should_accept, result.returncode))
        assert not failures, f'Filter misclassified dynamically generated CSV content: {failures[:5]}'


def _find_processes(script_path):
    found = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().decode('utf-8', 'replace').replace(chr(0), ' ')
            if script_path in cmdline:
                found.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def _upload_csv(content):
    boundary = '----verifier' + uuid.uuid4().hex
    filename = uuid.uuid4().hex + '.dat'
    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        'Content-Type: text/csv\r\n\r\n'
    ).encode() + content.encode() + f'\r\n--{boundary}--\r\n'.encode()

    last_error = None
    for _ in range(20):
        conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=2)
        try:
            conn.request('POST', '/upload', body=body, headers={
                'Content-Type': f'multipart/form-data; boundary={boundary}',
                'Content-Length': str(len(body)),
                'Connection': 'close',
            })
            response = conn.getresponse()
            response_body = response.read()
            return response.status, response_body
        except OSError as exc:
            last_error = exc
            time.sleep(0.25)
        finally:
            conn.close()
    raise AssertionError(f'API on port 8080 was not reachable: {last_error}')


def test_services_running_and_api_uses_filter():
    api_pids = _find_processes('/home/user/app/api.py')
    worker_pids = _find_processes('/home/user/app/worker.py')
    assert api_pids, 'Flask API process is not running.'
    assert worker_pids, 'Storage Worker process is not running.'

    client = redis.Redis(host='127.0.0.1', port=6379, socket_connect_timeout=2, socket_timeout=2)
    assert client.ping() is True, 'Redis is not running on port 6379.'

    clean_content = 'id,feature_A,feature_B,target\n0,-1000,12.5,0\n1,1000,-3,1\n'
    evil_content = 'id,feature_A,feature_B,target\n0,1001,12.5,0\n'

    stopped = []
    try:
        for pid in worker_pids:
            os.kill(pid, signal.SIGSTOP)
            stopped.append(pid)
        time.sleep(0.1)
        client.delete('data_queue')

        status, _ = _upload_csv(clean_content)
        assert status == 200, f'API did not accept a dynamically generated clean CSV; status={status}'
        queued = client.lpop('data_queue')
        assert queued == clean_content.encode(), 'API did not enqueue the accepted CSV content in Redis.'
        assert client.llen('data_queue') == 0

        status, _ = _upload_csv(evil_content)
        assert status == 400, f'API did not reject a dynamically generated evil CSV; status={status}'
        assert client.llen('data_queue') == 0, 'API enqueued CSV content rejected by the filter.'

        sentinel = ('worker-check-' + uuid.uuid4().hex).encode()
        client.rpush('data_queue', sentinel)
        for pid in stopped:
            os.kill(pid, signal.SIGCONT)
        stopped.clear()

        deadline = time.time() + 5
        while time.time() < deadline and client.llen('data_queue') != 0:
            time.sleep(0.1)
        assert client.llen('data_queue') == 0, 'Storage Worker did not consume an item from Redis.'
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
