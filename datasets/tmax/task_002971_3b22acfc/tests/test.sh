#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib

def test_archived_files():
    archive_dir = "/home/user/archived_gcode"
    assert os.path.isdir(archive_dir), f"Directory {archive_dir} does not exist"

    expected_files = ["print1.gcode", "print2.gcode", "print3.gcode"]
    for f in expected_files:
        path = os.path.join(archive_dir, f)
        assert os.path.isfile(path), f"Expected file {f} is missing from {archive_dir}"

def test_manifest_contents():
    manifest_path = "/home/user/gcode_manifest.jsonl"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist"

    expected_data = [
        ("print1.gcode", "G1 X10 Y10\nG1 Z0.2\n; filament used [mm] = 15.4\nM104 S0\n", 15.4),
        ("print2.gcode", "G28\nG1 X20 Y20\n; filament used [mm] = 3.2\nM140 S0\n", 3.2),
        ("print3.gcode", "M109 S200\nG1 X30 Y30\n; filament used [mm] = 100.0\nM104 S0\n", 100.0),
    ]

    expected_records = {}
    for fname, content, filament in expected_data:
        sha256 = hashlib.sha256(content.encode('utf-8')).hexdigest()
        expected_records[fname] = {
            "filename": fname,
            "sha256": sha256,
            "filament_mm": filament
        }

    with open(manifest_path, "r") as f:
        lines = f.read().strip().split('\n')

    # Ignore empty lines
    lines = [line for line in lines if line.strip()]

    assert len(lines) == 3, f"Expected 3 records in manifest, found {len(lines)}"

    parsed_records = {}
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in manifest is not valid JSON: {line}"

        assert "filename" in record, f"Line {i+1} missing 'filename' key"
        parsed_records[record["filename"]] = record

    for fname, expected in expected_records.items():
        assert fname in parsed_records, f"Manifest is missing record for {fname}"
        record = parsed_records[fname]
        assert record["sha256"] == expected["sha256"], f"Incorrect sha256 for {fname}. Expected {expected['sha256']}, got {record['sha256']}"
        assert float(record["filament_mm"]) == expected["filament_mm"], f"Incorrect filament_mm for {fname}. Expected {expected['filament_mm']}, got {record['filament_mm']}"

def test_processing_log_exists():
    log_path = "/home/user/processing.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_pipeline.py
import hashlib
import json
import os
import secrets
import shutil
import signal
import subprocess
import time
import uuid

SCRIPT = '/home/user/process_gcode.py'
INCOMING = '/home/user/incoming_gcode'
ARCHIVE = '/home/user/archived_gcode'
MANIFEST = '/home/user/gcode_manifest.jsonl'
LOG = '/home/user/processing.log'

assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist or is not a regular file'
assert not os.path.islink(SCRIPT), f'{SCRIPT} must be an actual script, not a symlink'
assert os.path.getsize(SCRIPT) > 0, f'{SCRIPT} is empty'

# Stop any previously launched copy so only the submitted artifact started below
# can process the verifier-generated files.
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    try:
        with open(f'/proc/{entry}/cmdline', 'rb') as f:
            argv = [part.decode(errors='ignore') for part in f.read().split(b'\0') if part]
        if SCRIPT in argv:
            os.kill(int(entry), signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
time.sleep(0.3)

for path in (INCOMING, ARCHIVE):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
for path in (MANIFEST, LOG):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

expected = {}
for index in range(4):
    name = f'verifier_{uuid.uuid4().hex}.gcode'
    whole = secrets.randbelow(9000) + 1
    fraction = secrets.randbelow(999) + 1
    value_text = f'{whole}.{fraction:03d}'
    content = (
        f'; randomized token {secrets.token_hex(20)}\n'
        f'G1 X{secrets.randbelow(500)} Y{secrets.randbelow(500)}\n'
        f'; not filament used [mm] = 999999\n'
        f'; filament used [mm] = {value_text}\n'
        f'M104 S{secrets.randbelow(250)}\n'
    ).encode('utf-8')
    expected[name] = {
        'filename': name,
        'sha256': hashlib.sha256(content).hexdigest(),
        'filament_mm': float(value_text),
        'content': content,
    }

log = open(LOG, 'ab', buffering=0)
env = os.environ.copy()
env['PYTHONUNBUFFERED'] = '1'
proc = subprocess.Popen(
    ['/usr/bin/python3', SCRIPT],
    cwd='/home/user',
    stdout=log,
    stderr=subprocess.STDOUT,
    env=env,
)

try:
    time.sleep(1.0)
    assert proc.poll() is None, f'{SCRIPT} exited before any files arrived with status {proc.returncode}'

    for name, item in expected.items():
        temporary = f'/tmp/{name}.{uuid.uuid4().hex}.tmp'
        with open(temporary, 'wb') as f:
            f.write(item['content'])
        os.replace(temporary, os.path.join(INCOMING, name))
        time.sleep(0.7)

    deadline = time.time() + 15
    last_error = None
    records = None
    while time.time() < deadline:
        try:
            assert proc.poll() is None, f'{SCRIPT} stopped while watching with status {proc.returncode}'
            with open(MANIFEST, 'r', encoding='utf-8') as f:
                lines = [line for line in f.read().splitlines() if line.strip()]
            parsed = [json.loads(line) for line in lines]
            assert len(parsed) == len(expected), f'expected {len(expected)} dynamic records, found {len(parsed)}'
            records = {record['filename']: record for record in parsed}
            assert set(records) == set(expected), 'manifest filenames do not match verifier-generated inputs'
            for name in expected:
                assert os.path.isfile(os.path.join(ARCHIVE, name)), f'{name} was not archived'
                assert not os.path.exists(os.path.join(INCOMING, name)), f'{name} remains in incoming directory'
            break
        except (AssertionError, FileNotFoundError, json.JSONDecodeError, KeyError) as exc:
            last_error = exc
            records = None
            time.sleep(0.25)

    assert records is not None, f'pipeline did not finish before timeout: {last_error}'
    assert proc.poll() is None, 'processor did not remain running as a watcher'

    for name, item in expected.items():
        record = records[name]
        assert set(record.keys()) == {'filename', 'sha256', 'filament_mm'}, f'incorrect manifest keys for {name}'
        assert record['filename'] == name
        assert record['sha256'] == item['sha256'], f'incorrect checksum for {name}'
        assert type(record['filament_mm']) is float, f'filament_mm for {name} is not a JSON float'
        assert record['filament_mm'] == item['filament_mm'], f'incorrect filament value for {name}'
        with open(os.path.join(ARCHIVE, name), 'rb') as f:
            assert f.read() == item['content'], f'archived content for {name} was changed'
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
    log.close()
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
if [ "$status" -eq 0 ]; then
    python3 /tmp/test_dynamic_pipeline.py 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
