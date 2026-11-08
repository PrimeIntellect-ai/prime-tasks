#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

import pytest
import requests

ARTIFACTS = Path('/app/data/artifacts')
SCRIPT = Path('/home/user/curate.py')
INDEX = Path('/app/data/backup_index.json')

ORIGINAL_GROUPS = [
    ['v1.0/libfoo1.so', 'v1.0/libfoo1_dup.so', 'v2.0/libfoo1.so'],
    ['v1.0/libfoo2.so', 'v1.0/libfoo2_dup.so', 'v2.0/libfoo2.so'],
    ['v1.0/libfoo3.so', 'v1.0/libfoo3_dup.so', 'v2.0/libfoo3.so'],
    ['v1.0/libfoo4.so', 'v2.0/libfoo4.so'],
]


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def repository_files():
    result = {}
    for root, dirs, files in os.walk(ARTIFACTS, followlinks=False):
        dirs.sort()
        files.sort()
        for name in files:
            path = Path(root) / name
            assert not path.is_symlink(), f'Artifact was replaced by a symbolic link: {path}'
            assert path.is_file(), f'Artifact is not a regular file: {path}'
            result[path.relative_to(ARTIFACTS).as_posix()] = path
    return result


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_curator():
    assert ARTIFACTS.is_dir(), f'Directory {ARTIFACTS} does not exist.'
    assert SCRIPT.is_file(), f'Curation script {SCRIPT} is missing.'
    assert not SCRIPT.is_symlink(), f'Curation script {SCRIPT} must be a real file.'

    # The original random artifacts cannot be recreated by the verifier, so ensure
    # that none were deleted or truncated before exercising the submitted script.
    original_hashes = []
    for group in ORIGINAL_GROUPS:
        group_hashes = []
        for relative in group:
            path = ARTIFACTS / relative
            assert path.is_file() and not path.is_symlink(), f'Missing original artifact: {relative}'
            assert path.stat().st_size == 50 * 1024 * 1024, f'Original artifact was truncated: {relative}'
            group_hashes.append(sha256_file(path))
        assert len(set(group_hashes)) == 1, f'Original duplicate contents were altered in group {group}'
        original_hashes.append(group_hashes[0])
    assert len(set(original_hashes)) == 4, 'The four original artifact contents must remain distinct.'

    # Add unpredictable duplicate files after the agent has finished, then run the
    # required script. This proves that curate.py itself discovers, hashes, and
    # hard-links repository contents rather than relying on a fabricated final state.
    probe = ARTIFACTS / ('verifier_probe_' + uuid.uuid4().hex)
    nested = probe / 'nested'
    nested.mkdir(parents=True)
    payload = os.urandom(1024 * 1024 + 137)
    master = probe / 'oldest.bin'
    duplicate1 = probe / 'duplicate.so'
    duplicate2 = nested / 'duplicate.jar'
    unique = nested / 'unique.bin'

    master.write_bytes(payload)
    old_time = time.time() - 86400
    os.utime(master, (old_time, old_time))
    time.sleep(0.05)
    duplicate1.write_bytes(payload)
    time.sleep(0.05)
    duplicate2.write_bytes(payload)
    unique_payload = os.urandom(65537)
    unique.write_bytes(unique_payload)

    master_stat = master.stat()
    assert len({master.stat().st_ino, duplicate1.stat().st_ino, duplicate2.stat().st_ino}) == 3

    try:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('curate.py did not finish within 180 seconds.')
    assert completed.returncode == 0, f'curate.py failed with output:\n{completed.stdout}'
    assert SCRIPT.is_file() and not SCRIPT.is_symlink(), 'curate.py disappeared or became a symlink.'

    for path in (master, duplicate1, duplicate2, unique):
        assert path.is_file() and not path.is_symlink(), f'Probe artifact was deleted or replaced: {path}'
    for path in (master, duplicate1, duplicate2):
        assert path.stat().st_size == len(payload), f'Probe artifact was truncated: {path}'
        assert sha256_file(path) == hashlib.sha256(payload).hexdigest(), f'Probe content changed: {path}'
        assert (path.stat().st_dev, path.stat().st_ino) == (master_stat.st_dev, master_stat.st_ino), (
            f'{path} is not a hard link to the oldest duplicate.'
        )
    assert unique.read_bytes() == unique_payload, 'A nonduplicate probe artifact was altered.'

    # Every remaining equal-content group, including the original artifacts, must
    # share one physical inode rather than merely having been shortened or deleted.
    by_hash = {}
    for relative, path in repository_files().items():
        by_hash.setdefault(sha256_file(path), []).append((relative, path))
    for digest, entries in by_hash.items():
        if len(entries) > 1:
            inodes = {(path.stat().st_dev, path.stat().st_ino) for _, path in entries}
            assert len(inodes) == 1, f'Duplicate content {digest} was not fully hard-linked: {[x[0] for x in entries]}'


def test_services_running_and_configured():
    try:
        res = requests.get('http://127.0.0.1:8080/health', timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to the health endpoint. Is Nginx running on port 8080? Error: {exc}')
    assert res.status_code == 200, f'Expected status code 200, got {res.status_code}'
    try:
        data = res.json()
    except ValueError:
        pytest.fail('Health endpoint did not return valid JSON.')
    assert data == {'status': 'ok'}, f"Expected health endpoint to return {{'status': 'ok'}}, got {data}"


def test_disk_usage_metric():
    assert ARTIFACTS.exists(), f'Directory {ARTIFACTS} does not exist.'
    try:
        out = subprocess.check_output(['du', '-sk', str(ARTIFACTS)], text=True)
        size_kb = int(out.split()[0])
    except Exception as exc:
        pytest.fail(f'Failed to compute disk usage for {ARTIFACTS}. Error: {exc}')
    threshold = 210000
    assert size_kb <= threshold, (
        f'Disk usage {size_kb} KB exceeded threshold of {threshold} KB. '
        'Deduplication via hard links was not completely successful.'
    )


def test_curate_script_exists():
    assert SCRIPT.is_file(), f'Curation script {SCRIPT} is missing.'


def test_backup_index_exists_and_valid():
    assert INDEX.is_file(), f'Backup index file {INDEX} is missing.'
    try:
        with open(INDEX, 'r') as handle:
            data = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f'Backup index file {INDEX} does not contain valid JSON.')

    assert isinstance(data, dict), f'Expected backup index to be a JSON dictionary, got {type(data).__name__}.'
    assert len(data) > 0, 'Backup index JSON dictionary is empty.'
    for path, file_hash in data.items():
        assert isinstance(path, str), f'Expected path to be a string, got {type(path).__name__}.'
        assert isinstance(file_hash, str) and len(file_hash) == 64, (
            f"Expected hash to be a 64-character string (SHA-256), got '{file_hash}' for path '{path}'."
        )

    expected = {relative: sha256_file(path) for relative, path in repository_files().items()}
    assert data == expected, (
        'backup_index.json must map every current repository-relative file path '
        'to its recomputed SHA-256 hash, with no missing or fabricated entries.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
