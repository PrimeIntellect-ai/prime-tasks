#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_backup_agent.py
import os
import pathlib
import py_compile
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
import time

import pytest

SCRIPT = pathlib.Path('/home/user/backup_agent.py')
BASE = pathlib.Path('/home/user')
LOGS = BASE / 'logs'
ARCHIVES = BASE / 'archives'
INCOMING = BASE / 'incoming'
CORRUPTED = BASE / 'corrupted_archives.txt'


def reset_directories():
    for path in (LOGS, ARCHIVES, INCOMING):
        shutil.rmtree(path, ignore_errors=True)
        path.mkdir(parents=True, exist_ok=True)
    if CORRUPTED.exists() or CORRUPTED.is_symlink():
        CORRUPTED.unlink()


def wait_for(path, process, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.is_file():
            return
        if process.poll() is not None:
            pytest.fail(f'backup_agent.py exited early with code {process.returncode}')
        time.sleep(0.1)
    pytest.fail(f'Timed out waiting for {path}')


def run_with_incoming(names_and_contents):
    process = subprocess.Popen(
        [sys.executable, str(SCRIPT)],
        cwd=str(BASE),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(1)
        assert process.poll() is None, 'backup_agent.py exited before receiving 3 log files'

        for index, (name, content) in enumerate(names_and_contents):
            source = INCOMING / name
            source.write_bytes(content)
            destination = LOGS / ('processed_' + name)
            wait_for(destination, process)
            assert destination.read_bytes() == content
            assert not source.exists()
            if index < 2:
                assert process.poll() is None, 'backup_agent.py exited before processing exactly 3 files'

        try:
            return_code = process.wait(timeout=12)
        except subprocess.TimeoutExpired:
            pytest.fail('backup_agent.py did not exit after processing the third log file')
        assert return_code == 0, f'backup_agent.py exited with code {return_code}'
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def create_archive(path, member_name='payload.txt'):
    payload = BASE / member_name
    payload.write_text('valid archive payload')
    try:
        with tarfile.open(path, 'w:gz') as archive:
            archive.add(payload, arcname=member_name)
    finally:
        payload.unlink()


def test_00_script_execution_and_dynamic_behavior():
    assert SCRIPT.exists(), f'Missing required script: {SCRIPT}'
    assert stat.S_ISREG(SCRIPT.lstat().st_mode), 'backup_agent.py must be a regular file'
    py_compile.compile(str(SCRIPT), doraise=True)

    reset_directories()
    token = secrets.token_hex(8)
    nested = LOGS / ('nested_' + token)
    nested.mkdir()

    old_name = f'old {token}.log'
    old_path = LOGS / old_name
    old_content = b'old dynamic log\n'
    old_path.write_bytes(old_content)
    old_time = time.time() - 9 * 24 * 60 * 60
    os.utime(old_path, (old_time, old_time))

    large_name = f'large {token}.log'
    large_path = nested / large_name
    large_path.write_bytes(b'L' * 1048577)

    boundary_name = f'boundary {token}.log'
    boundary_path = LOGS / boundary_name
    boundary_path.write_bytes(b'B' * 1048576)

    normal_name = f'normal {token}.log'
    normal_path = nested / normal_name
    normal_content = b'recent small log\n'
    normal_path.write_bytes(normal_content)

    valid_archive = ARCHIVES / f'valid_{token}.tar.gz'
    corrupt_a = ARCHIVES / f'corrupt_{token}_z.tar.gz'
    corrupt_b = ARCHIVES / f'corrupt_{token}_a.tar.gz'
    create_archive(valid_archive, f'payload_{token}.txt')
    corrupt_a.write_bytes(secrets.token_bytes(53))
    corrupt_b.write_bytes(b'not a tar archive ' + secrets.token_bytes(17))

    incoming = [
        (f'event_{token}_a.log', secrets.token_bytes(31)),
        (f'event_{token}_b.log', secrets.token_bytes(47)),
        (f'event_{token}_c.log', secrets.token_bytes(63)),
    ]
    run_with_incoming(incoming)

    renamed_old = LOGS / f'archive_old_{token}.log'
    renamed_large = nested / f'archive_large_{token}.log'
    assert renamed_old.is_file()
    assert renamed_old.read_bytes() == old_content
    assert not old_path.exists()
    assert renamed_large.is_file()
    assert renamed_large.stat().st_size == 1048577
    assert not large_path.exists()
    assert boundary_path.is_file(), 'A file exactly 1 MiB must not be renamed'
    assert not (LOGS / f'archive_boundary_{token}.log').exists()
    assert normal_path.is_file() and normal_path.read_bytes() == normal_content
    assert not (nested / f'archive_normal_{token}.log').exists()

    assert CORRUPTED.is_file()
    lines = [line.strip() for line in CORRUPTED.read_text().splitlines() if line.strip()]
    expected = sorted([str(corrupt_a), str(corrupt_b)])
    assert lines == expected
    assert str(valid_archive) not in lines

    # Recreate the original fixtures and execute once more so the original
    # final-state assertions below remain intact.
    reset_directories()
    (LOGS / 'subdir').mkdir()
    original_old = LOGS / 'old app.log'
    original_old.touch()
    os.utime(original_old, (old_time, old_time))
    (LOGS / 'subdir' / 'large file.log').write_bytes(b'X' * (2 * 1048576))
    (LOGS / 'normal.log').write_text('normal log\n')
    create_archive(ARCHIVES / 'backup_valid.tar.gz', 'normal.log')
    (ARCHIVES / 'backup_corrupted.tar.gz').write_text('this is not a valid tarball\n')
    (ARCHIVES / 'bad_archive.tar.gz').write_text('garbage\n')
    run_with_incoming([
        ('file1.log', b'fixture one\n'),
        ('file2.log', b'fixture two\n'),
        ('file3.log', b'fixture three\n'),
    ])


def test_renamed_logs():
    """Verify that logs meeting the criteria were renamed properly, and others were ignored."""
    archive_old = "/home/user/logs/archive_old_app.log"
    original_old = "/home/user/logs/old app.log"
    archive_large = "/home/user/logs/subdir/archive_large_file.log"
    original_large = "/home/user/logs/subdir/large file.log"
    normal_log = "/home/user/logs/normal.log"
    archive_normal = "/home/user/logs/archive_normal.log"

    assert os.path.isfile(archive_old), f"Expected renamed file missing: {archive_old}"
    assert not os.path.exists(original_old), f"Original file should have been renamed: {original_old}"
    assert os.path.isfile(archive_large), f"Expected renamed file missing: {archive_large}"
    assert not os.path.exists(original_large), f"Original file should have been renamed: {original_large}"
    assert os.path.isfile(normal_log), f"Normal log should not have been modified: {normal_log}"
    assert not os.path.exists(archive_normal), f"Normal log was incorrectly renamed to: {archive_normal}"


def test_corrupted_archives():
    """Verify that the corrupted_archives.txt file exists and contains the correct sorted paths."""
    corrupted_file_path = "/home/user/corrupted_archives.txt"
    assert os.path.isfile(corrupted_file_path), f"File missing: {corrupted_file_path}"
    with open(corrupted_file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_corrupt = [
        "/home/user/archives/backup_corrupted.tar.gz",
        "/home/user/archives/bad_archive.tar.gz"
    ]
    expected_corrupt.sort()
    assert lines == expected_corrupt, f"Contents of {corrupted_file_path} do not match expected sorted paths. Expected {expected_corrupt}, got {lines}"


def test_processed_incoming_files():
    """Verify that the 3 incoming files were detected, renamed, and moved to the logs directory."""
    for i in range(1, 4):
        processed_file = f"/home/user/logs/processed_file{i}.log"
        incoming_file = f"/home/user/incoming/file{i}.log"
        assert os.path.isfile(processed_file), f"Processed incoming file is missing: {processed_file}"
        assert not os.path.exists(incoming_file), f"Incoming file was not removed from incoming directory: {incoming_file}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_backup_agent.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
