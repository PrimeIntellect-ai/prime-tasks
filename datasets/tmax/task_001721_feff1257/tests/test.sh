#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PREP_EOF' > /tmp/prepare_dynamic_fixture.py
import json
import os
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

root = Path('/home/user/deployments')
tag = secrets.token_hex(8)
fixture_dir = root / f'verifier_{tag}' / 'nested'
fixture_dir.mkdir(parents=True, exist_ok=True)

managed = fixture_dir / f'managed_{tag}.ini'
no_log = fixture_dir / f'no_log_{tag}.ini'
not_writable = fixture_dir / f'not_writable_{tag}.ini'

managed.write_text(f'name={tag}\nvalue=dynamic\n', encoding='utf-8')
no_log.write_text('present=true\n', encoding='utf-8')
not_writable.write_text('locked=true\n', encoding='utf-8')
os.chmod(managed, 0o664)
os.chmod(no_log, 0o664)
os.chmod(not_writable, 0o644)

old_ts = f'2037-01-{secrets.randbelow(20) + 1:02d}T01:02:03Z'
mid_ts = f'2040-06-{secrets.randbelow(20) + 1:02d}T04:05:06Z'
latest_ts = f'2042-11-{secrets.randbelow(20) + 1:02d}T07:08:09Z'

# Put the newest record before an older record so implementations must compare
# timestamps across complete multi-line records rather than taking the last hit.
records = [
    (str(managed), latest_ts, ['+ value=dynamic', '- value=old']),
    (str(not_writable), mid_ts, ['+ locked=true']),
    (str(managed), old_ts, ['+ name=initial']),
    (str(managed), mid_ts, ['+ name=middle', '+ another=line']),
]
with open('/home/user/audit/changes.log', 'a', encoding='utf-8') as log:
    for path, timestamp, diffs in records:
        log.write('---BEGIN RECORD---\n')
        log.write(f'File: {path}\n')
        log.write(f'Timestamp: {timestamp}\n')
        log.write('Changes:\n')
        for line in diffs:
            log.write(line + '\n')
        log.write('---END RECORD---\n')

with open('/tmp/verifier_fixture.json', 'w', encoding='utf-8') as f:
    json.dump({
        'managed': str(managed),
        'no_log': str(no_log),
        'not_writable': str(not_writable),
    }, f)


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table, encoding='ascii').read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                inodes.add(fields[9])
    owners = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    owners.append(int(name))
                    break
        except OSError:
            pass
    return owners

pids = listener_pids(9090)
if not pids:
    raise RuntimeError('No process is listening on port 9090')

pid = pids[0]
with open(f'/proc/{pid}/cmdline', 'rb') as f:
    argv = [part.decode(errors='surrogateescape') for part in f.read().split(b'\0') if part]
if not argv:
    raise RuntimeError('Unable to recover server command line')
cwd = os.readlink(f'/proc/{pid}/cwd')
environ = {}
with open(f'/proc/{pid}/environ', 'rb') as f:
    for item in f.read().split(b'\0'):
        if b'=' in item:
            key, value = item.split(b'=', 1)
            environ[key.decode(errors='surrogateescape')] = value.decode(errors='surrogateescape')
executable = os.readlink(f'/proc/{pid}/exe')
restart_argv = [executable] + argv[1:]

for owner in pids:
    try:
        os.kill(owner, signal.SIGTERM)
    except ProcessLookupError:
        pass
for _ in range(50):
    if not listener_pids(9090):
        break
    time.sleep(0.1)
else:
    for owner in listener_pids(9090):
        try:
            os.kill(owner, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)

log_file = open('/tmp/verifier-restarted-server.log', 'ab', buffering=0)
subprocess.Popen(restart_argv, cwd=cwd, env=environ, stdin=subprocess.DEVNULL,
                 stdout=log_file, stderr=log_file, start_new_session=True)

for _ in range(100):
    try:
        with socket.create_connection(('127.0.0.1', 9090), timeout=0.2):
            break
    except OSError:
        time.sleep(0.1)
else:
    raise RuntimeError('Restarted server did not listen on port 9090')
PREP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import requests
import pytest

BASE_URL = "http://127.0.0.1:9090"


def get_golden_hash(filepath):
    """Dynamically execute the binary to get the expected hash for a given file."""
    binary_path = "/app/hash_checker"
    assert os.path.isfile(binary_path), f"Missing binary {binary_path}"
    result = subprocess.run([binary_path, filepath], capture_output=True, text=True, check=True)
    return result.stdout.strip()


def latest_timestamp_from_log(filepath):
    timestamps = []
    with open('/home/user/audit/changes.log', encoding='utf-8') as f:
        text = f.read()
    for portion in text.split('---BEGIN RECORD---')[1:]:
        if '---END RECORD---' not in portion:
            continue
        record = portion.split('---END RECORD---', 1)[0]
        record_path = None
        timestamp = None
        for line in record.splitlines():
            if line.startswith('File: '):
                record_path = line[len('File: '):]
            elif line.startswith('Timestamp: '):
                timestamp = line[len('Timestamp: '):]
            elif line == 'Changes:':
                break
        if record_path == filepath and timestamp is not None:
            timestamps.append(timestamp)
    assert timestamps, f'Fixture has no log timestamp for {filepath}'
    return max(timestamps)


def test_app1_config_success():
    filepath = "/home/user/deployments/app1/config.ini"
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})

    assert response.status_code == 200, f"Expected 200 OK for {filepath}, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "latest_update" in data, "Response JSON missing 'latest_update' key"
    assert "hash" in data, "Response JSON missing 'hash' key"

    expected_timestamp = "2023-10-05T15:30:00Z"
    expected_hash = get_golden_hash(filepath)

    assert data["latest_update"] == expected_timestamp, f"Expected timestamp {expected_timestamp}, got {data['latest_update']}"
    assert data["hash"] == expected_hash, f"Expected hash {expected_hash}, got {data['hash']}"


def test_app2_settings_success():
    filepath = "/home/user/deployments/app2/settings.ini"
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})

    assert response.status_code == 200, f"Expected 200 OK for {filepath}, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "latest_update" in data, "Response JSON missing 'latest_update' key"
    assert "hash" in data, "Response JSON missing 'hash' key"

    expected_timestamp = "2023-10-02T11:00:00Z"
    expected_hash = get_golden_hash(filepath)

    assert data["latest_update"] == expected_timestamp, f"Expected timestamp {expected_timestamp}, got {data['latest_update']}"
    assert data["hash"] == expected_hash, f"Expected hash {expected_hash}, got {data['hash']}"


def test_app3_ignore_not_group_writable():
    filepath = "/home/user/deployments/app3/ignore.ini"
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})

    assert response.status_code == 404, f"Expected 404 Not Found for {filepath} (not group-writable), got {response.status_code}"


def test_nonexistent_file():
    filepath = "/home/user/deployments/nonexistent.ini"
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})

    assert response.status_code == 404, f"Expected 404 Not Found for {filepath}, got {response.status_code}"


def fixture():
    with open('/tmp/verifier_fixture.json', encoding='utf-8') as f:
        return json.load(f)


def test_dynamic_nested_managed_file_and_multirecord_log():
    filepath = fixture()['managed']
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})
    assert response.status_code == 200, f"Expected 200 OK for dynamic managed file {filepath}, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "latest_update" in data, "Response JSON missing 'latest_update' key"
    assert "hash" in data, "Response JSON missing 'hash' key"
    expected_timestamp = latest_timestamp_from_log(filepath)
    expected_hash = get_golden_hash(filepath)
    assert data['latest_update'] == expected_timestamp, f"Expected timestamp {expected_timestamp}, got {data['latest_update']}"
    assert data['hash'] == expected_hash, f"Expected hash {expected_hash}, got {data['hash']}"


def test_dynamic_group_writable_file_without_log_is_404():
    filepath = fixture()['no_log']
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})
    assert response.status_code == 404, f"Expected 404 for group-writable file without log entries, got {response.status_code}"


def test_dynamic_logged_but_not_group_writable_file_is_404():
    filepath = fixture()['not_writable']
    response = requests.get(f"{BASE_URL}/status", params={"file": filepath})
    assert response.status_code == 404, f"Expected 404 for logged file without g+w permission, got {response.status_code}"
TEST_EOF

rc=0
python3 /tmp/prepare_dynamic_fixture.py || rc=1
if [ "$rc" -eq 0 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || rc=1
fi

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
