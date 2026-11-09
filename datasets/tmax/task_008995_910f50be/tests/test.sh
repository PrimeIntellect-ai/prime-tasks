#!/bin/bash
mkdir -p /logs/verifier

if (
set -e

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_chunk_1_exists_and_content():
    path = "/home/user/processed/chunk_1.json"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")
    expected_data = [
        {"hostname": "srv1", "used_gb": 85},
        {"hostname": "srv3", "used_gb": 190}
    ]
    assert data == expected_data, f"Content of {path} does not match expected output. Got: {data}"

def test_chunk_2_exists_and_content():
    path = "/home/user/processed/chunk_2.json"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")
    expected_data = [
        {"hostname": "srv4", "used_gb": 450},
        {"hostname": "srv6", "used_gb": 90}
    ]
    assert data == expected_data, f"Content of {path} does not match expected output. Got: {data}"

def test_chunk_3_does_not_exist():
    path = "/home/user/processed/chunk_3.json"
    assert not os.path.exists(path), f"File {path} should not exist."

def test_watcher_go_exists():
    path = "/home/user/watcher.go"
    assert os.path.isfile(path), f"Expected Go source file {path} does not exist."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

python3 - << 'PY'
import os
import re

source_path = "/home/user/watcher.go"
module_path = "/home/user/go.mod"
assert os.path.isfile(source_path), "watcher.go is missing"
assert os.path.isfile(module_path), "go.mod is missing"

source = open(source_path, encoding="utf-8").read()
module = open(module_path, encoding="utf-8").read()
assert '"github.com/fsnotify/fsnotify"' in source, "watcher.go must import github.com/fsnotify/fsnotify"
assert "github.com/fsnotify/fsnotify" in module, "go.mod must require github.com/fsnotify/fsnotify"

selector = re.search(r"\b([A-Za-z_]\w*)\s*\.\s*NewWatcher\s*\(", source)
uses_dot_import = re.search(r"(?m)^\s*\.\s+\"github.com/fsnotify/fsnotify\"\s*$", source)
if selector:
    alias = re.escape(selector.group(1))
    assert re.search(r"\b" + alias + r"\s*\.\s*Create\b", source), "watcher.go must handle fsnotify Create events"
elif uses_dot_import:
    assert re.search(r"\bNewWatcher\s*\(", source), "watcher.go must create an fsnotify watcher"
    assert re.search(r"\bCreate\b", source), "watcher.go must handle fsnotify Create events"
else:
    raise AssertionError("watcher.go must call fsnotify.NewWatcher")
PY

# Stop any watcher left by the agent so only the submitted source built below can
# satisfy the behavioral test.
python3 - << 'PY'
import os
import signal
import time

me = os.getpid()
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == me:
        continue
    try:
        cmd = open(f'/proc/{entry}/cmdline', 'rb').read().replace(b'\0', b' ')
    except OSError:
        continue
    if b'watcher.go' in cmd or b'/exe/watcher' in cmd or b'/home/user/watcher ' in cmd:
        try:
            os.kill(int(entry), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
time.sleep(0.5)
PY

cd /home/user
go build -o /tmp/watcher-verifier watcher.go

python3 - /tmp/watcher-verifier << 'PY'
import glob
import json
import os
import random
import secrets
import signal
import subprocess
import sys
import time

binary = sys.argv[1]
incoming = "/home/user/incoming"
processed = "/home/user/processed"
os.makedirs(incoming, exist_ok=True)
os.makedirs(processed, exist_ok=True)
for directory in (incoming, processed):
    for path in glob.glob(os.path.join(directory, "*")):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

log = open('/tmp/watcher-verifier.log', 'w+')
proc = subprocess.Popen([binary], cwd='/home/user', stdout=log, stderr=subprocess.STDOUT)
try:
    time.sleep(1.0)
    assert proc.poll() is None, "built watcher exited before a CREATE event"
    assert not glob.glob(os.path.join(processed, 'chunk_*.json')), "watcher produced chunks before a CSV was created"

    token = secrets.token_hex(6)
    used_values = [80, random.randint(81, 120), random.randint(121, 250), 0,
                   random.randint(251, 500), 79, random.randint(501, 900)]
    rows = []
    for i, used in enumerate(used_values):
        rows.append((f"host-{token}-{i}", random.randint(50, 2000), used, f"state-{i}"))

    expected_objects = [
        {"hostname": hostname, "used_gb": used}
        for hostname, _, used, _ in rows if used > 80
    ]
    expected_chunks = [expected_objects[i:i + 2] for i in range(0, len(expected_objects), 2)]

    # Populate the file completely outside the watched directory, then rename it
    # into place. On Linux this produces the watched directory's CREATE event.
    temp_path = f"/home/user/.verifier-{token}.csv"
    with open(temp_path, 'w', newline='') as f:
        f.write('Hostname,DiskSizeGB,UsedGB,Status\n')
        for hostname, size, used, status in rows:
            f.write(f'{hostname},{size},{used},{status}\n')
    report_path = os.path.join(incoming, f'report-{token}.csv')
    os.rename(temp_path, report_path)

    deadline = time.time() + 12
    last_error = None
    while time.time() < deadline:
        try:
            actual = []
            for index in range(1, len(expected_chunks) + 1):
                path = os.path.join(processed, f'chunk_{index}.json')
                with open(path, encoding='utf-8') as f:
                    chunk = json.load(f)
                assert isinstance(chunk, list), f"{path} must contain a JSON array"
                assert 1 <= len(chunk) <= 2, f"{path} has an invalid chunk size"
                for obj in chunk:
                    assert set(obj) == {'hostname', 'used_gb'}, f"invalid object schema in {path}"
                    assert type(obj['used_gb']) is int, f"used_gb in {path} must be an integer"
                actual.append(chunk)
            assert actual == expected_chunks, f"dynamic output mismatch: {actual!r}"
            files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(processed, 'chunk_*.json')))
            wanted = [f'chunk_{i}.json' for i in range(1, len(expected_chunks) + 1)]
            assert files == wanted, f"unexpected chunk files: {files!r}"
            assert proc.poll() is None, "watcher exited after processing one event"
            break
        except (AssertionError, FileNotFoundError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(0.15)
    else:
        log.seek(0)
        raise AssertionError(f"watcher did not process the dynamic CREATE event: {last_error}; log={log.read()}")
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    log.close()
PY

); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
