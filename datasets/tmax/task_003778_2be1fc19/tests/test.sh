#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import uuid
import tarfile
import subprocess

PROJECT = '/home/user/project'
ARCHIVE = os.path.join(PROJECT, 'archive.tar.gz')
SNAPSHOT = os.path.join(PROJECT, 'data_snapshot.log')
DATA_LOG = os.path.join(PROJECT, 'data.log')
STATUS = os.path.join(PROJECT, 'status.txt')
SYMLINK = os.path.join(PROJECT, 'latest_archive.tar.gz')


def wait_for_writer():
    pid_file = os.path.join(PROJECT, 'writer.pid')
    if not os.path.exists(pid_file):
        return
    with open(pid_file, 'r') as f:
        pid_text = f.read().strip()
    if not pid_text.isdigit():
        return
    pid = int(pid_text)
    cmdline_path = f'/proc/{pid}/cmdline'
    if not os.path.exists(cmdline_path):
        return
    try:
        with open(cmdline_path, 'rb') as f:
            cmdline = f.read().decode(errors='ignore')
    except OSError:
        return
    if 'writer.py' not in cmdline:
        return
    deadline = time.time() + 45
    while os.path.exists(cmdline_path) and time.time() < deadline:
        time.sleep(0.1)
    assert not os.path.exists(cmdline_path), 'Background writer did not finish normally.'


def submitted_script():
    candidates = [
        os.path.join(PROJECT, 'rotate.sh'),
        os.path.join(PROJECT, 'rotate.py'),
    ]
    existing = [p for p in candidates if os.path.isfile(p) and not os.path.islink(p)]
    assert existing, 'No regular rotate.sh or rotate.py submission was created.'
    path = existing[0]
    with open(path, 'r', errors='replace') as f:
        source = f.read()
    assert source.strip(), 'Submitted rotation script is empty.'
    assert re.search(r'\btarfile\b|\bshutil\b|\btar\s|\bgzip\s', source), \
        'Rotation script contains no archive creation or integrity-check operation.'
    return path


def run_script(path, timeout=20):
    command = ['python3', path] if path.endswith('.py') else ['bash', path]
    proc = subprocess.run(command, cwd=PROJECT, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=timeout)
    assert proc.returncode == 0, \
        f'Rotation script failed with code {proc.returncode}: {proc.stdout}{proc.stderr}'


def clean_outputs():
    for path in (ARCHIVE, SNAPSHOT, STATUS, SYMLINK):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def archive_snapshot():
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        members = [m for m in tar.getmembers() if m.name.endswith('data_snapshot.log')]
        assert members, 'data_snapshot.log not found in archive.tar.gz'
        f = tar.extractfile(members[0])
        assert f is not None, 'Failed to extract data_snapshot.log from archive'
        return f.read().decode('utf-8')


def assert_fresh_outputs(expected_combined):
    assert os.path.isfile(ARCHIVE), f'{ARCHIVE} does not exist.'
    assert os.path.isfile(SNAPSHOT), f'{SNAPSHOT} does not exist.'
    assert os.path.isfile(STATUS), f'{STATUS} does not exist.'
    assert os.path.getsize(STATUS) > 0, f'{STATUS} is empty.'
    assert os.path.islink(SYMLINK), f'{SYMLINK} is not a symbolic link.'
    assert os.path.realpath(SYMLINK) == os.path.realpath(ARCHIVE), \
        'latest_archive.tar.gz does not resolve to archive.tar.gz.'

    archived = archive_snapshot()
    with open(SNAPSHOT, 'r') as f:
        external_snapshot = f.read()
    with open(DATA_LOG, 'r') as f:
        current = f.read()
    assert archived == external_snapshot, \
        'The archived snapshot differs from data_snapshot.log.'
    assert archived + current == expected_combined, \
        'Concurrent rotation lost, duplicated, or reordered log data.'

    with open(STATUS, 'r', errors='replace') as f:
        status = f.read()
    lower = status.lower()
    assert ('data_snapshot.log' in status or
            re.search(r'archive[^\n]*(ok|valid)|(ok|valid)[^\n]*archive', lower)), \
        'status.txt does not contain recognizable archive integrity-check output.'


def test_submission_is_executed_and_locks_log():
    wait_for_writer()
    script = submitted_script()

    # These artifacts must already exist from the execution requested of the agent.
    assert os.path.isfile(ARCHIVE), 'archive.tar.gz was not created before verification.'
    assert os.path.isfile(STATUS), 'status.txt was not created before verification.'
    assert os.path.islink(SYMLINK), 'latest_archive.tar.gz was not created before verification.'

    clean_outputs()
    with open(DATA_LOG, 'w'):
        pass

    token = 'audit-' + uuid.uuid4().hex
    lines = [f'{token}:{i}\n' for i in range(120)]
    expected = ''.join(lines)
    ready = '/tmp/rotation_writer_ready_' + uuid.uuid4().hex
    helper_path = '/tmp/rotation_lock_writer.py'
    with open(helper_path, 'w') as f:
        f.write(r'''import fcntl, os, sys, time
path, ready, token = sys.argv[1:4]
with open(path, 'a') as log:
    fcntl.flock(log, fcntl.LOCK_EX)
    open(ready, 'w').close()
    for i in range(60):
        log.write(f'{token}:{i}\n')
        log.flush()
        time.sleep(0.02)
    fcntl.flock(log, fcntl.LOCK_UN)
for i in range(60, 120):
    with open(path, 'a') as log:
        fcntl.flock(log, fcntl.LOCK_EX)
        log.write(f'{token}:{i}\n')
        log.flush()
        fcntl.flock(log, fcntl.LOCK_UN)
    time.sleep(0.005)
''')

    writer = subprocess.Popen(['python3', helper_path, DATA_LOG, ready, token])
    deadline = time.time() + 5
    while not os.path.exists(ready) and time.time() < deadline:
        time.sleep(0.01)
    assert os.path.exists(ready), 'Controlled writer failed to acquire its lock.'

    command = ['python3', script] if script.endswith('.py') else ['bash', script]
    rotation = subprocess.Popen(command, cwd=PROJECT, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
    time.sleep(0.25)
    assert writer.poll() is None, 'Controlled writer unexpectedly exited while testing the lock.'
    assert rotation.poll() is None, \
        'Rotation completed while another process still held an exclusive lock on data.log.'

    out, err = rotation.communicate(timeout=20)
    assert rotation.returncode == 0, \
        f'Rotation script failed with code {rotation.returncode}: {out}{err}'
    assert writer.wait(timeout=20) == 0, 'Controlled writer failed.'
    assert_fresh_outputs(expected)

    # Re-run on the original fixed sequence so the original final-state assertions
    # continue to be checked after the behavioral test.
    clean_outputs()
    with open(DATA_LOG, 'w') as f:
        for i in range(3000):
            f.write(f'Log entry {i}\n')
    run_script(script)


def test_symlink_created_correctly():
    symlink_path = '/home/user/project/latest_archive.tar.gz'
    assert os.path.islink(symlink_path), f'{symlink_path} is not a symbolic link.'
    target = os.readlink(symlink_path)
    assert target.endswith('archive.tar.gz'), f'Symlink points to {target}, expected it to point to archive.tar.gz.'


def test_status_file_exists_and_not_empty():
    status_path = '/home/user/project/status.txt'
    assert os.path.isfile(status_path), f'{status_path} does not exist.'
    assert os.path.getsize(status_path) > 0, f'{status_path} is empty.'


def test_log_rotation_integrity():
    wait_for_writer()

    archive_path = '/home/user/project/archive.tar.gz'
    assert os.path.isfile(archive_path), f'{archive_path} does not exist.'

    snapshot_data = ''
    with tarfile.open(archive_path, 'r:gz') as tar:
        snapshot_member = None
        for member in tar.getmembers():
            if member.name.endswith('data_snapshot.log'):
                snapshot_member = member
                break
        assert snapshot_member is not None, 'data_snapshot.log not found in archive.tar.gz'

        f = tar.extractfile(snapshot_member)
        assert f is not None, 'Failed to extract data_snapshot.log from archive'
        snapshot_data = f.read().decode('utf-8')

    data_log_path = '/home/user/project/data.log'
    assert os.path.isfile(data_log_path), f'{data_log_path} does not exist.'

    with open(data_log_path, 'r') as f:
        data_log = f.read()

    combined = snapshot_data + data_log
    lines = [line for line in combined.split('\n') if line]

    assert len(lines) == 3000, f'Expected exactly 3000 log entries, but found {len(lines)}. Data loss or duplication occurred.'

    for i, line in enumerate(lines):
        expected_line = f'Log entry {i}'
        assert line == expected_line, f"Sequence broken at line {i+1}. Expected '{expected_line}', got '{line}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
