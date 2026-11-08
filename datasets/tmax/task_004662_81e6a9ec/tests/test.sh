#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import zlib
import pytest

BASE_DIR = '/home/user/data'
LOG_PATH = '/home/user/backup_history.log'
TARGET_BACKUP = '/home/user/latest_backup.zlib'

ORIGINAL_LOG = b'''--- Backup Record ---
Status: SUCCESS
Timestamp: 1690000000
Files: 10
---------------------
--- Backup Record ---
Status: SUCCESS
Timestamp: 1696161600
Files: 5
---------------------
--- Backup Record ---
Status: FAILED
Timestamp: 1697000000
Files: 0
---------------------
'''


def get_latest_success_timestamp(log_path):
    assert os.path.exists(log_path), f"Log file {log_path} missing."
    with open(log_path, 'r') as f:
        content = f.read()

    records = content.split('--- Backup Record ---')
    max_ts = -1
    for record in records:
        if not record.strip():
            continue
        if 'Status: SUCCESS' in record:
            match = re.search(r'Timestamp:\s*(\d+)', record)
            if match:
                ts = int(match.group(1))
                if ts > max_ts:
                    max_ts = ts
    return max_ts


def get_exact_latest_success_timestamp(log_path):
    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read()
    latest = -1
    for record in content.split('--- Backup Record ---'):
        status = re.search(r'^Status:\s*(.*?)\s*$', record, re.MULTILINE)
        timestamp = re.search(r'^Timestamp:\s*(\d+)\s*$', record, re.MULTILINE)
        if status and timestamp and status.group(1) == 'SUCCESS':
            latest = max(latest, int(timestamp.group(1)))
    return latest


def build_expected_archive(base_dir, min_mtime):
    files_to_archive = []
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            full_path = os.path.join(root, file)
            if os.path.islink(full_path):
                continue

            stat_result = os.stat(full_path)
            if stat_result.st_mtime > min_mtime:
                rel_path = os.path.relpath(full_path, base_dir)
                files_to_archive.append(rel_path)

    files_to_archive.sort()

    archive_parts = []
    for rel_path in files_to_archive:
        full_path = os.path.join(base_dir, rel_path)
        size = os.path.getsize(full_path)
        with open(full_path, 'rb') as f:
            content = f.read().decode('utf-8')
        archive_parts.append(f"{rel_path}\n{size}\n{content}")

    return "".join(archive_parts)


def assert_original_inputs_unchanged():
    with open(LOG_PATH, 'rb') as f:
        assert f.read() == ORIGINAL_LOG, 'backup_history.log was modified.'

    assert sorted(os.listdir(BASE_DIR)) == ['file1.txt', 'file2.txt', 'loop', 'subdir'], \
        'The original data directory was modified.'
    assert sorted(os.listdir(os.path.join(BASE_DIR, 'subdir'))) == ['file3.txt'], \
        'The original data directory was modified.'

    expected = {
        'file1.txt': (b'old content', 1693526400),
        'file2.txt': (b'new data 1', 1696982400),
        'subdir/file3.txt': (b'new data 2', 1697760000),
    }
    for rel_path, (contents, mtime) in expected.items():
        path = os.path.join(BASE_DIR, rel_path)
        st = os.lstat(path)
        assert stat.S_ISREG(st.st_mode), f'{rel_path} is no longer a regular file.'
        with open(path, 'rb') as f:
            assert f.read() == contents, f'{rel_path} contents were modified.'
        assert st.st_mtime_ns == mtime * 1_000_000_000, f'{rel_path} mtime was modified.'

    loop = os.path.join(BASE_DIR, 'loop')
    assert os.path.islink(loop), 'The required symlink loop was removed or replaced.'
    assert os.readlink(loop) == BASE_DIR, 'The symlink loop target was modified.'


def discover_python_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user', followlinks=False):
        if root == '/home/user':
            dirs[:] = [d for d in dirs if d != 'data']
        for name in files:
            path = os.path.join(root, name)
            if path in (LOG_PATH, TARGET_BACKUP) or os.path.islink(path):
                continue
            try:
                if stat.S_ISREG(os.stat(path).st_mode):
                    candidates.append(path)
            except OSError:
                pass
    return sorted(candidates)


def reset_original_inputs():
    if os.path.lexists(BASE_DIR):
        shutil.rmtree(BASE_DIR)
    os.makedirs(os.path.join(BASE_DIR, 'subdir'))
    files = {
        'file1.txt': (b'old content', 1693526400),
        'file2.txt': (b'new data 1', 1696982400),
        'subdir/file3.txt': (b'new data 2', 1697760000),
    }
    for rel_path, (contents, mtime) in files.items():
        path = os.path.join(BASE_DIR, rel_path)
        with open(path, 'wb') as f:
            f.write(contents)
        os.utime(path, (mtime, mtime))
    os.symlink(BASE_DIR, os.path.join(BASE_DIR, 'loop'))
    with open(LOG_PATH, 'wb') as f:
        f.write(ORIGINAL_LOG)


def install_random_scenario():
    if os.path.lexists(BASE_DIR):
        shutil.rmtree(BASE_DIR)
    os.makedirs(os.path.join(BASE_DIR, 'a', 'deep'))
    token = secrets.token_hex(12)
    files = {
        'equal.txt': (f'equal-{token}'.encode(), 1800000200),
        'old.txt': (f'old-{token}'.encode(), 1800000100),
        'z-new.txt': (f'zulu-{token}'.encode(), 1800000201),
        'a/deep/new.txt': (f'nested-{token}'.encode(), 1800000300),
    }
    for rel_path, (contents, mtime) in files.items():
        path = os.path.join(BASE_DIR, rel_path)
        with open(path, 'wb') as f:
            f.write(contents)
        os.utime(path, (mtime, mtime))

    os.symlink(BASE_DIR, os.path.join(BASE_DIR, 'loop'))
    os.symlink(os.path.join(BASE_DIR, 'z-new.txt'), os.path.join(BASE_DIR, 'linked-file'))

    log = '''--- Backup Record ---
Status: SUCCESS
Timestamp: 1800000100
---------------------
--- Backup Record ---
Status: SUCCESSFUL
Timestamp: 1999999999
---------------------
--- Backup Record ---
Status: FAILED
Timestamp: 1900000000
---------------------
--- Backup Record ---
Status: SUCCESS
Timestamp: 1800000200
---------------------
'''
    with open(LOG_PATH, 'w', encoding='utf-8') as f:
        f.write(log)


def snapshot_inputs():
    result = [('log', open(LOG_PATH, 'rb').read())]

    def visit(path, rel):
        for entry in sorted(os.scandir(path), key=lambda e: e.name):
            child_rel = os.path.join(rel, entry.name)
            st = os.lstat(entry.path)
            if stat.S_ISLNK(st.st_mode):
                result.append(('symlink', child_rel, os.readlink(entry.path), st.st_mode))
            elif stat.S_ISDIR(st.st_mode):
                result.append(('dir', child_rel, st.st_mode))
                visit(entry.path, child_rel)
            elif stat.S_ISREG(st.st_mode):
                with open(entry.path, 'rb') as f:
                    result.append(('file', child_rel, f.read(), st.st_mtime_ns, st.st_mode))
            else:
                result.append(('other', child_rel, st.st_mode))

    visit(BASE_DIR, '')
    return result


def run_script(script):
    if os.path.lexists(TARGET_BACKUP):
        os.unlink(TARGET_BACKUP)
    return subprocess.run(
        ['python3', script],
        cwd=os.path.dirname(script) or '/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        text=True,
    )


def assert_archive_matches(expected_data):
    assert os.path.exists(TARGET_BACKUP), f'Backup file {TARGET_BACKUP} was not created.'
    with open(TARGET_BACKUP, 'rb') as f:
        compressed_data = f.read()
    try:
        decompressed_data = zlib.decompress(compressed_data).decode('utf-8')
    except Exception as e:
        pytest.fail(f'Failed to decompress {TARGET_BACKUP}: {e}')
    assert decompressed_data == expected_data, (
        f'Decompressed data does not match expected output.\n'
        f'Expected:\n{expected_data!r}\nGot:\n{decompressed_data!r}'
    )
    assert compressed_data == zlib.compress(expected_data.encode('utf-8')), \
        'Archive was not produced by zlib.compress() with its default level.'


def test_latest_backup_zlib_content():
    # First preserve the original verifier's check, while ensuring its inputs are
    # still the fixture that the requested backup was supposed to process.
    assert_original_inputs_unchanged()
    latest_success_ts = get_latest_success_timestamp(LOG_PATH)
    assert latest_success_ts != -1, 'Could not find a successful backup timestamp in the log.'
    expected_data = build_expected_archive(BASE_DIR, latest_success_ts)
    assert_archive_matches(expected_data)

    scripts = discover_python_scripts()
    assert scripts, 'No Python backup script was written under /home/user.'

    failures = []
    for script in scripts:
        try:
            reset_original_inputs()
            original_expected = build_expected_archive(
                BASE_DIR, get_latest_success_timestamp(LOG_PATH)
            )
            before = snapshot_inputs()
            result = run_script(script)
            if result.returncode != 0:
                raise AssertionError(f'exited {result.returncode}: {result.stderr[-500:]}')
            assert snapshot_inputs() == before, 'Script modified its input data or history.'
            assert_archive_matches(original_expected)

            install_random_scenario()
            min_mtime = get_exact_latest_success_timestamp(LOG_PATH)
            assert min_mtime == 1800000200
            random_expected = build_expected_archive(BASE_DIR, min_mtime)
            before = snapshot_inputs()
            result = run_script(script)
            if result.returncode != 0:
                raise AssertionError(f'exited {result.returncode}: {result.stderr[-500:]}')
            assert snapshot_inputs() == before, 'Script modified its input data or history.'
            assert_archive_matches(random_expected)
            return
        except Exception as e:
            failures.append(f'{script}: {e}')

    pytest.fail('No submitted Python script produced the required backup when executed.\n' +
                '\n'.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
