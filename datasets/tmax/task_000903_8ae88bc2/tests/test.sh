#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import shlex
import subprocess
import time
import uuid

import pytest

OUTPUT_PATH = '/home/user/error_archive.json'
LOG_PATH = '/home/user/active_service.log'


def test_error_archive_exists_and_valid():
    output_path = OUTPUT_PATH

    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"The path {output_path} is not a file."

    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The file {output_path} does not contain valid JSON: {e}")

    assert isinstance(data, list), "The JSON output must be an array (list) of objects."
    assert len(data) == 2, f"Expected exactly 2 ERROR records, but found {len(data)}."

    # Check first record
    assert data[0].get("TIMESTAMP") == "2023-10-25T10:01:00Z", "First record TIMESTAMP mismatch."
    assert data[0].get("LEVEL") == "ERROR", "First record LEVEL mismatch."
    assert data[0].get("MSG") == "Volume shadow copy failed", "First record MSG mismatch."
    assert data[0].get("DETAILS") == "VSS writer error 0x8004231f", "First record DETAILS mismatch."

    # Check second record
    assert data[1].get("TIMESTAMP") == "2023-10-25T10:05:00Z", "Second record TIMESTAMP mismatch."
    assert data[1].get("LEVEL") == "ERROR", "Second record LEVEL mismatch."
    assert data[1].get("MSG") == "Network timeout", "Second record MSG mismatch."
    assert data[1].get("DETAILS") == "Destination unreachable after 30s", "Second record DETAILS mismatch."

    # Ensure no extra keys are present and no [RECORD] markers
    for record in data:
        for key, value in record.items():
            assert "[RECORD]" not in key and "[/RECORD]" not in key, f"Marker found in key: {key}"
            assert "[RECORD]" not in str(value) and "[/RECORD]" not in str(value), f"Marker found in value: {value}"


def candidate_scripts():
    roots = ['/home/user', '/tmp', '/opt', '/root', '/usr/local/bin']
    excluded = {
        os.path.realpath('/home/user/setup_log.py'),
        os.path.realpath(LOG_PATH),
        os.path.realpath(OUTPUT_PATH),
        os.path.realpath('/tmp/test_final_state.py'),
    }
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__', '.git'}]
            for name in files:
                path = os.path.join(directory, name)
                real = os.path.realpath(path)
                if real in excluded or not os.path.isfile(path):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, 'rb') as f:
                        raw = f.read()
                    text = raw.decode('utf-8', errors='ignore')
                except OSError:
                    continue
                if 'active_service.log' not in text or 'error_archive.json' not in text:
                    continue
                if not (name.endswith(('.py', '.sh', '.bash', '.pl', '.rb', '.js')) or raw.startswith(b'#!')):
                    continue
                found.append(path)
    return sorted(set(found))


def command_for(path):
    if path.endswith('.py'):
        return ['python3', path]
    if path.endswith(('.sh', '.bash')):
        return ['bash', path]
    if path.endswith('.pl'):
        return ['perl', path]
    if path.endswith('.rb'):
        return ['ruby', path]
    if path.endswith('.js'):
        return ['node', path]
    with open(path, 'rb') as f:
        first = f.readline().decode('utf-8', errors='ignore').strip()
    if first.startswith('#!'):
        return shlex.split(first[2:].strip()) + [path]
    return [path]


def has_blocked_shared_flock(inode):
    try:
        with open('/proc/locks', 'r', encoding='ascii') as f:
            for line in f:
                if ('->' in line and 'FLOCK' in line and 'READ' in line
                        and f':{inode} ' in line):
                    return True
    except OSError:
        pass
    return False


def exercise_script(path, encoded_log, expected):
    proc = None
    reason = 'script did not run'
    with open(LOG_PATH, 'wb') as locked_log:
        locked_log.write(encoded_log)
        locked_log.flush()
        os.fsync(locked_log.fileno())
        inode = os.fstat(locked_log.fileno()).st_ino
        fcntl.flock(locked_log, fcntl.LOCK_EX)

        try:
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            proc = subprocess.Popen(
                command_for(path), cwd=os.path.dirname(path) or '/',
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )

            deadline = time.time() + 4
            observed_shared_waiter = False
            while time.time() < deadline:
                if has_blocked_shared_flock(inode):
                    observed_shared_waiter = True
                    break
                if proc.poll() is not None:
                    break
                time.sleep(0.03)

            if not observed_shared_waiter:
                reason = 'no blocked shared flock was observed while an exclusive lock was held'
                return False, reason
        finally:
            fcntl.flock(locked_log, fcntl.LOCK_UN)

    try:
        stdout, stderr = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        return False, 'script did not finish after the exclusive lock was released'

    if proc.returncode != 0:
        return False, f'script exited {proc.returncode}: {stderr.decode(errors="replace")}'
    if not os.path.isfile(OUTPUT_PATH):
        return False, 'script did not create error_archive.json'
    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            actual = json.load(f)
    except Exception as exc:
        return False, f'script output was not valid UTF-8 JSON: {exc}'
    if actual != expected:
        return False, f'script did not parse the replacement UTF-16LE log correctly: {actual!r}'
    return True, ''


def test_script_executes_parses_utf16le_and_uses_shared_flock():
    scripts = candidate_scripts()
    assert scripts, 'No archival script was found.'

    token = uuid.uuid4().hex
    expected = [
        {
            'TIMESTAMP': '2042-07-08T09:10:11Z',
            'LEVEL': 'ERROR',
            'MSG': f'Unicode café failure {token}',
            'DETAILS': f'Snowman ☃ detail {token}',
        },
        {
            'TIMESTAMP': '2042-07-08T09:12:13Z',
            'LEVEL': 'ERROR',
            'MSG': f'Second dynamic error {token}',
            'DETAILS': f'Path /dynamic/{token}',
        },
    ]
    log_text = f'''[RECORD]
TIMESTAMP: 2042-07-08T09:00:00Z
LEVEL: INFO
MSG: Decoy {token}
DETAILS: Must not be archived
[/RECORD]
[RECORD]
TIMESTAMP: {expected[0]["TIMESTAMP"]}
LEVEL: ERROR
MSG:   {expected[0]["MSG"]}   
DETAILS:   {expected[0]["DETAILS"]}   
[/RECORD]
[RECORD]
TIMESTAMP: 2042-07-08T09:11:12Z
LEVEL: WARNING
MSG: Warning decoy
DETAILS: Also excluded {token}
[/RECORD]
[RECORD]
TIMESTAMP: {expected[1]["TIMESTAMP"]}
LEVEL: ERROR
MSG: {expected[1]["MSG"]}
DETAILS: {expected[1]["DETAILS"]}
[/RECORD]
'''

    with open(LOG_PATH, 'rb') as f:
        original_log = f.read()
    with open(OUTPUT_PATH, 'rb') as f:
        original_output = f.read()

    failures = []
    try:
        for script in scripts:
            ok, reason = exercise_script(script, log_text.encode('utf-16le'), expected)
            if ok:
                return
            failures.append(f'{script}: {reason}')
        pytest.fail('No submitted script passed dynamic execution:\n' + '\n'.join(failures))
    finally:
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        with open(OUTPUT_PATH, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
