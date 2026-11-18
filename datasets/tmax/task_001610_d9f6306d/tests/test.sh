#!/bin/bash
set -Eeuo pipefail
mkdir -p /logs/verifier
REWARD=0
SERVER_PID=""

kill_port_8080() {
    python3 - <<'PY'
import os
import signal
import time

for _ in range(5):
    inodes = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    if inodes:
        for pid in os.listdir('/proc'):
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            fd_dir = f'/proc/{pid}/fd'
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f'{fd_dir}/{fd}')
                    except OSError:
                        continue
                    if target.startswith('socket:[') and target[8:-1] in inodes:
                        victims.add(int(pid))
                        break
            except OSError:
                pass

    if not victims:
        break
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
PY
}

stop_server() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill -- "-${SERVER_PID}" 2>/dev/null || true
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
        SERVER_PID=""
    fi
    kill_port_8080 || true
}

finish() {
    stop_server
    printf '%s\n' "$REWARD" > /logs/verifier/reward.txt
}
trap finish EXIT

start_server() {
    kill_port_8080
    : > /tmp/config_tracker_server.log
    setsid cargo run --release --quiet --manifest-path /home/user/config_tracker/Cargo.toml \
        > /tmp/config_tracker_server.log 2>&1 &
    SERVER_PID=$!

    python3 - "$SERVER_PID" <<'PY'
import os
import sys
import time
import urllib.request

pid = int(sys.argv[1])
deadline = time.time() + 180
while time.time() < deadline:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        raise AssertionError('The submitted Rust application exited before serving HTTP')
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/status', timeout=1) as response:
            if response.status == 200:
                sys.exit(0)
    except Exception:
        time.sleep(0.25)
raise AssertionError('The Rust HTTP server did not become reachable on 127.0.0.1:8080')
PY
}

# Require and execute the requested Rust project rather than trusting an already-running process.
test -f /home/user/config_tracker/Cargo.toml
find /home/user/config_tracker -type f -name '*.rs' -print -quit | grep -q .
stop_server

# First retain all assertions from the original verifier against the writer's canonical archive.
rm -rf /home/user/wal_archive
mkdir -p /home/user/wal_archive
/app/config_writer
start_server

python3 - <<'PY'
import json
import time
import urllib.error
import urllib.request

BASE = 'http://127.0.0.1:8080'

def get(path):
    try:
        with urllib.request.urlopen(BASE + path, timeout=2) as response:
            return response.status, json.loads(response.read().decode() or '{}')
    except urllib.error.HTTPError as error:
        body = error.read().decode()
        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            data = {}
        return error.code, data

deadline = time.time() + 20
while time.time() < deadline:
    status, data = get('/status')
    if status == 200 and data.get('files_processed') == 3:
        break
    time.sleep(0.25)
else:
    raise AssertionError('Expected 3 files processed')

status, data = get('/config/max_connections')
assert status == 200, f'Expected 200 OK for max_connections, got {status}'
assert data.get('key') == 'max_connections', f"Expected key 'max_connections', got {data.get('key')}"
assert data.get('value') == 2048, f"Expected value 2048 for max_connections, got {data.get('value')}"

status, _ = get('/config/timeout')
assert status == 404, f'Expected 404 Not Found for timeout, got {status}'

status, data = get('/status')
assert status == 200, f'Expected 200 OK for /status, got {status}'
assert data.get('files_processed') == 3, f"Expected 3 files processed, got {data.get('files_processed')}"
PY

stop_server

# Build a fresh, unpredictable WAL corpus using the proprietary writer's actual record layout.
rm -rf /home/user/wal_archive
mkdir -p /home/user/wal_archive
python3 - <<'PY'
import gzip
import json
import os
import secrets
import struct

archive = '/home/user/wal_archive'
keys = ['audit_' + secrets.token_hex(8) for _ in range(5)]
values = [secrets.randbelow(2_000_000_000) + 1 for _ in range(12)]
file_count = 4 + secrets.randbelow(3)
ts = 50000
state = {}

def write_file(number, records):
    global ts
    path = os.path.join(archive, f'wal_{number:04d}.gz')
    with gzip.open(path, 'wb') as output:
        for op, key, value in records:
            ts += 1
            encoded = key.encode()
            output.write(struct.pack('<QBI', ts, op, len(encoded)))
            output.write(encoded)
            if op == 1:
                output.write(struct.pack('<i', value))
                state[key] = value
            else:
                state.pop(key, None)

write_file(1, [(1, keys[0], values[0]), (1, keys[3], values[1])])
write_file(2, [(1, keys[1], values[2]), (1, keys[0], values[3])])
write_file(3, [(2, keys[3], None), (1, keys[2], values[4])])
for number in range(4, file_count + 1):
    key = keys[(number - 4) % 3]
    write_file(number, [(1, key, values[number + 1])])

live_records = [
    (1, keys[1], values[9]),
    (2, keys[2], None),
    (1, keys[4], values[10]),
]
with open('/tmp/wal_expectations.json', 'w') as output:
    json.dump({
        'initial_state': state,
        'initial_files': file_count,
        'deleted_key': keys[3],
        'missing_key': 'missing_' + secrets.token_hex(8),
        'live_records': live_records,
        'live_file': file_count + 1,
        'next_timestamp': ts + 1,
    }, output)
PY

start_server

python3 - <<'PY'
import gzip
import json
import os
import struct
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = 'http://127.0.0.1:8080'
with open('/tmp/wal_expectations.json') as source:
    expected = json.load(source)

def get(path):
    try:
        with urllib.request.urlopen(BASE + path, timeout=2) as response:
            return response.status, json.loads(response.read().decode() or '{}')
    except urllib.error.HTTPError as error:
        body = error.read().decode()
        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            data = {}
        return error.code, data

def wait_for_files(count, timeout=25):
    deadline = time.time() + timeout
    while time.time() < deadline:
        status, data = get('/status')
        if status == 200 and data.get('files_processed') == count:
            return
        time.sleep(0.25)
    raise AssertionError(f'Expected files_processed to become {count}')

def assert_value(key, value):
    status, data = get('/config/' + urllib.parse.quote(key, safe=''))
    assert status == 200, f'Expected 200 for generated key {key}, got {status}'
    assert data.get('key') == key, f'Wrong key in response for {key}: {data}'
    assert data.get('value') == value, f'Wrong value for {key}: {data}'

wait_for_files(expected['initial_files'])
for key, value in expected['initial_state'].items():
    assert_value(key, value)
for key in (expected['deleted_key'], expected['missing_key']):
    status, _ = get('/config/' + urllib.parse.quote(key, safe=''))
    assert status == 404, f'Expected 404 for absent generated key {key}, got {status}'

# Add another rotated WAL after startup to verify ongoing state tracking rather than a static response table.
path = f"/home/user/wal_archive/wal_{expected['live_file']:04d}.gz"
ts = expected['next_timestamp']
with gzip.open(path, 'wb') as output:
    for op, key, value in expected['live_records']:
        encoded = key.encode()
        output.write(struct.pack('<QBI', ts, op, len(encoded)))
        output.write(encoded)
        if op == 1:
            output.write(struct.pack('<i', value))
        ts += 1

wait_for_files(expected['live_file'])
for op, key, value in expected['live_records']:
    if op == 1:
        assert_value(key, value)
    else:
        status, _ = get('/config/' + urllib.parse.quote(key, safe=''))
        assert status == 404, f'Expected dynamically deleted key {key} to return 404, got {status}'
PY

REWARD=1
