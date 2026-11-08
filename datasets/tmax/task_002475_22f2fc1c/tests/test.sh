#!/bin/bash
set -e
mkdir -p /logs/verifier
DAEMON_PID=""
cleanup() {
    if [ -n "$DAEMON_PID" ]; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import zipfile


def matching_entry(zf, suffix):
    matches = [name for name in zf.namelist() if name.endswith(suffix) and not name.endswith('/')]
    assert len(matches) == 1, f"Expected exactly one ZIP entry ending in {suffix!r}, found {matches!r}."
    return matches[0]


def test_zip_exists():
    """Test that the output zip file exists."""
    zip_path = '/home/user/outgoing/payload.zip'
    assert os.path.isfile(zip_path), f"The output zip file {zip_path} is missing. The daemon may not have processed the archive."


def test_zip_contents():
    """Test that the output zip file contains the correct chunked and untouched files."""
    zip_path = '/home/user/outgoing/payload.zip'
    assert os.path.isfile(zip_path), f"The output zip file {zip_path} is missing."

    with zipfile.ZipFile(zip_path, 'r') as zf:
        namelist = zf.namelist()

        expected_files = [
            'massive_data.bin.part0',
            'massive_data.bin.part1',
            'massive_data.bin.part2',
            'info.txt',
            'edge_case.bin'
        ]

        for ef in expected_files:
            assert any(f.endswith(ef) for f in namelist), f"Expected file {ef} not found in zip archive."

        assert not any(f.endswith('massive_data.bin') or f == 'massive_data.bin' for f in namelist), \
            "The original unchunked file massive_data.bin was found in the zip. It should have been removed after chunking."

        part_names = [matching_entry(zf, f'massive_data.bin.part{i}') for i in range(3)]
        part_data = [zf.read(name) for name in part_names]
        assert [len(data) for data in part_data] == [1024000, 1024000, 452000]

        with open('/tmp/payload_src/massive_data.bin', 'rb') as f:
            expected_large = f.read()
        assert b''.join(part_data) == expected_large, "The chunks do not reconstruct the original massive_data.bin."

        for filename in ('info.txt', 'edge_case.bin'):
            entry = matching_entry(zf, filename)
            with open('/tmp/payload_src/' + filename, 'rb') as f:
                expected = f.read()
            assert zf.read(entry) == expected, f"ZIP contents for {filename} do not match the original file."


def test_log_file():
    """Test that the JSONL log file contains the correct entry."""
    log_path = '/home/user/artifact_log.jsonl'
    assert os.path.isfile(log_path), f"The log file {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) >= 1, "Log file is empty."

    parsed = None
    for line in lines:
        if not line.strip():
            continue
        try:
            data = json.loads(line)
            if data.get("original_archive") == "payload.tar.gz":
                parsed = data
                break
        except json.JSONDecodeError:
            continue

    assert parsed is not None, "Could not find a valid JSON log entry for 'payload.tar.gz'."
    assert parsed.get("repackaged_archive") == "payload.zip", "The 'repackaged_archive' value is incorrect."

    chunked_files = parsed.get("chunked_files", {})
    assert "massive_data.bin" in chunked_files, "'massive_data.bin' is missing from the 'chunked_files' object."
    assert chunked_files["massive_data.bin"] == 3, "'massive_data.bin' should be chunked into exactly 3 parts."
    assert len(chunked_files) == 1, "The 'chunked_files' object should only contain files that were actually chunked (only massive_data.bin)."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_daemon.py
import io
import json
import os
import secrets
import shutil
import tarfile
import time
import zipfile

manager_id = 'verifier_' + secrets.token_hex(8)
archive_name = manager_id + '.tar.gz'
zip_name = manager_id + '.zip'
large_name = 'random_large_' + secrets.token_hex(4) + '.bin'
edge_name = 'random_edge_' + secrets.token_hex(4) + '.bin'
small_name = 'random_small_' + secrets.token_hex(4) + '.txt'

large = os.urandom(2 * 1024000 + 12345)
edge = os.urandom(1024000)
small = os.urandom(317)
files = {large_name: large, edge_name: edge, small_name: small}

tmp_archive = '/tmp/' + archive_name
with tarfile.open(tmp_archive, 'w:gz') as tf:
    for name, data in files.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o644
        tf.addfile(info, io.BytesIO(data))

incoming = '/home/user/incoming/' + archive_name
outgoing = '/home/user/outgoing/' + zip_name
shutil.move(tmp_archive, incoming)

deadline = time.time() + 25
while time.time() < deadline:
    if os.path.isfile(outgoing):
        try:
            with zipfile.ZipFile(outgoing, 'r') as zf:
                zf.testzip()
            break
        except (OSError, zipfile.BadZipFile):
            pass
    time.sleep(0.25)
else:
    raise AssertionError(f'Daemon did not produce {outgoing} for a newly generated archive.')

with zipfile.ZipFile(outgoing, 'r') as zf:
    names = [n for n in zf.namelist() if not n.endswith('/')]

    def one(suffix):
        matches = [n for n in names if n.endswith(suffix)]
        assert len(matches) == 1, f'Expected one entry ending in {suffix!r}, got {matches!r}'
        return matches[0]

    chunks = [zf.read(one(large_name + f'.part{i}')) for i in range(3)]
    assert [len(c) for c in chunks] == [1024000, 1024000, 12345]
    assert b''.join(chunks) == large
    assert not any(n.endswith(large_name) for n in names)
    assert zf.read(one(edge_name)) == edge
    assert zf.read(one(small_name)) == small
    assert not any(n.endswith(edge_name + '.part0') for n in names), 'Exactly-threshold file was incorrectly chunked.'
    assert set(names) == {
        one(large_name + '.part0'), one(large_name + '.part1'), one(large_name + '.part2'),
        one(edge_name), one(small_name)
    }, f'Unexpected ZIP entries: {names!r}'

log_deadline = time.time() + 5
entry = None
while time.time() < log_deadline:
    if os.path.isfile('/home/user/artifact_log.jsonl'):
        with open('/home/user/artifact_log.jsonl', encoding='utf-8') as f:
            for line in f:
                try:
                    candidate = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if candidate.get('original_archive') == archive_name:
                    entry = candidate
    if entry is not None:
        break
    time.sleep(0.2)

assert entry is not None, 'No log entry was written for the verifier-generated archive.'
assert entry == {
    'original_archive': archive_name,
    'repackaged_archive': zip_name,
    'chunked_files': {large_name: 3},
}, f'Incorrect log entry: {entry!r}'
DYNAMIC_EOF

run_verification() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    python3 - << 'PY' || return 1
import os
main = '/home/user/artifact_manager/main.go'
mod = '/home/user/artifact_manager/go.mod'
assert os.path.isfile(main) and os.path.getsize(main) > 0, 'main.go is missing or empty.'
assert os.path.isfile(mod) and os.path.getsize(mod) > 0, 'go.mod is missing or empty.'
found = False
for root, dirs, files in os.walk('/home/user/artifact_manager'):
    for name in files:
        path = os.path.join(root, name)
        try:
            if os.access(path, os.X_OK) and open(path, 'rb').read(4) == b'\x7fELF':
                found = True
                break
        except OSError:
            pass
    if found:
        break
assert found, 'No compiled executable was found in /home/user/artifact_manager.'
PY

    (cd /home/user/artifact_manager && go build -o /tmp/artifact_manager_verifier_daemon .) || return 1

    # Stop the agent's user-owned daemon so the freshly compiled submitted source
    # is the process exercised by the unpredictable archive below.
    pkill -u user 2>/dev/null || true
    sleep 0.5
    /tmp/artifact_manager_verifier_daemon >/tmp/artifact_manager_verifier.stdout 2>/tmp/artifact_manager_verifier.stderr &
    DAEMON_PID=$!
    sleep 1
    kill -0 "$DAEMON_PID" 2>/dev/null || return 1

    python3 /tmp/test_dynamic_daemon.py || return 1
    kill -0 "$DAEMON_PID" 2>/dev/null || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
