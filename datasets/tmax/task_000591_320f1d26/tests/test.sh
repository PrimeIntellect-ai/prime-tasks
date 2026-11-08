#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import fcntl
import glob
import gzip
import hashlib
import math
import os
import secrets
import subprocess
import time

SCRIPT_PATH = '/home/user/archiver.py'
LOG_DIR = '/home/user/raw_logs'
ARCHIVE_DIR = '/home/user/archive'
CHUNK_SIZE = 10000000


def get_dir_size(path):
    total = 0
    if not os.path.exists(path):
        return 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total += os.path.getsize(fp)
    return total


def test_archiver_script_exists():
    script_path = '/home/user/archiver.py'
    assert os.path.isfile(script_path), f"The script {script_path} was not found."


def test_original_log_removed():
    log_path = '/home/user/raw_logs/system.log'
    assert not os.path.exists(log_path), f"The original log file {log_path} was not removed."


def test_archive_directory_and_files():
    archive_dir = '/home/user/archive'
    assert os.path.isdir(archive_dir), f"The archive directory {archive_dir} does not exist."

    chunks = glob.glob(os.path.join(archive_dir, 'system.log.chunk*.gz'))
    assert len(chunks) > 0, "No compressed chunk files found in the archive directory."


def test_archive_size_metric():
    archive_dir = '/home/user/archive'
    size = get_dir_size(archive_dir)
    threshold = 1500000
    assert size <= threshold, f"Archive size {size} bytes exceeds the threshold of {threshold} bytes."


def test_script_references_fcntl_flock():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    module_aliases = set()
    flock_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'fcntl':
                    module_aliases.add(item.asname or 'fcntl')
        elif isinstance(node, ast.ImportFrom) and node.module == 'fcntl':
            for item in node.names:
                if item.name == 'flock':
                    flock_aliases.add(item.asname or 'flock')

    has_flock_reference = bool(flock_aliases)
    for node in ast.walk(tree):
        if (isinstance(node, ast.Attribute) and node.attr == 'flock' and
                isinstance(node.value, ast.Name) and node.value.id in module_aliases):
            has_flock_reference = True

    assert has_flock_reference, 'archiver.py does not use fcntl.flock.'


def test_system_archive_integrity_and_chunking():
    line = b'{"level": "INFO", "message": "System check OK", "timestamp": "2023-10-01T12:00:00Z"}\n'
    expected_size = len(line) * 600000
    expected_count = math.ceil(expected_size / CHUNK_SIZE)
    expected_paths = [
        os.path.join(ARCHIVE_DIR, f'system.log.chunk{i}.gz')
        for i in range(expected_count)
    ]
    actual_paths = glob.glob(os.path.join(ARCHIVE_DIR, 'system.log.chunk*.gz'))
    assert set(actual_paths) == set(expected_paths), (
        f'Expected exactly {expected_count} contiguous system.log chunks; got {actual_paths}'
    )

    expected_hash = hashlib.sha256()
    batch = line * 10000
    for _ in range(60):
        expected_hash.update(batch)

    actual_hash = hashlib.sha256()
    total = 0
    for index, path in enumerate(expected_paths):
        expected_chunk_size = min(CHUNK_SIZE, expected_size - index * CHUNK_SIZE)
        chunk_size = 0
        with gzip.open(path, 'rb') as stream:
            while True:
                data = stream.read(1024 * 1024)
                if not data:
                    break
                chunk_size += len(data)
                assert chunk_size <= expected_chunk_size, f'{path} decompresses beyond its expected chunk size.'
                actual_hash.update(data)
        assert chunk_size == expected_chunk_size, (
            f'{path} decompresses to {chunk_size} bytes, expected {expected_chunk_size}.'
        )
        total += chunk_size

    assert total == expected_size
    assert actual_hash.digest() == expected_hash.digest(), 'Archived data does not reconstruct the original log.'


def test_script_executes_and_obeys_live_file_lock():
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(ARCHIVE_DIR, exist_ok=True)

    token = secrets.token_hex(8)
    filename = f'lock_probe_{token}.log'
    log_path = os.path.join(LOG_DIR, filename)
    archive_pattern = os.path.join(ARCHIVE_DIR, filename + '.chunk*.gz')

    seed = os.urandom(4096)
    payload_size = CHUNK_SIZE + 12345
    payload = (seed * ((payload_size + len(seed) - 1) // len(seed)))[:payload_size]

    with open(log_path, 'wb+') as locked_file:
        locked_file.write(payload)
        locked_file.flush()
        os.fsync(locked_file.fileno())
        fcntl.flock(locked_file.fileno(), fcntl.LOCK_EX)

        proc = subprocess.Popen(
            ['python3', SCRIPT_PATH],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        violation = None
        deadline = time.time() + 5
        try:
            while time.time() < deadline:
                if not os.path.exists(log_path):
                    violation = 'The script removed a log while another process held an exclusive lock.'
                    break
                if glob.glob(archive_pattern):
                    violation = 'The script archived a log while another process held an exclusive lock.'
                    break
                if proc.poll() is not None:
                    break
                time.sleep(0.1)
        finally:
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_UN)

    if proc.poll() is None:
        proc.wait(timeout=30)
    assert proc.returncode == 0, f'Executing archiver.py failed with status {proc.returncode}.'
    assert violation is None, violation

    # A nonblocking implementation may correctly skip the locked file, so run it
    # once more after releasing the lock if necessary.
    if os.path.exists(log_path):
        completed = subprocess.run(
            ['python3', SCRIPT_PATH],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        assert completed.returncode == 0, f'Executing archiver.py failed with status {completed.returncode}.'

    assert not os.path.exists(log_path), 'The executed script did not remove the successfully archived probe log.'
    expected_paths = [
        os.path.join(ARCHIVE_DIR, filename + '.chunk0.gz'),
        os.path.join(ARCHIVE_DIR, filename + '.chunk1.gz'),
    ]
    assert set(glob.glob(archive_pattern)) == set(expected_paths), 'Probe chunks were not named or counted correctly.'

    rebuilt = bytearray()
    for index, path in enumerate(expected_paths):
        with gzip.open(path, 'rb') as stream:
            data = stream.read()
        expected_length = CHUNK_SIZE if index == 0 else 12345
        assert len(data) == expected_length, f'Probe chunk {index} has the wrong decompressed size.'
        rebuilt.extend(data)
    assert bytes(rebuilt) == payload, 'Probe chunks do not reconstruct the dynamically generated input.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
