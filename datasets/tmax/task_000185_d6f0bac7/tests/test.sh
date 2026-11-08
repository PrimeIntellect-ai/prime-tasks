#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import struct
import subprocess
import zlib

import pytest

ARCHIVE = '/home/user/backup.bin'
PACKER = '/home/user/pack.go'
UNPACKER = '/app/config_unpacker'
EXTRACT_DIR = '/tmp/extract_test'


def expected_files():
    random.seed(42)
    result = {}
    for i in range(100):
        data = bytearray()
        for _ in range(800):
            key = f"config_key_{random.randint(1, 50)}".encode()
            val = f"{random.randint(1, 500)}".encode()
            data.extend(key + b"=" + val + b"\n")
        result[f'file_{i}.conf'] = bytes(data)
    return result


def run_packer():
    st = os.lstat(PACKER)
    assert os.path.isfile(PACKER), f'{PACKER} is not a regular file'
    assert not os.path.islink(PACKER), f'{PACKER} must not be a symlink'

    if os.path.lexists(ARCHIVE):
        os.remove(ARCHIVE)

    cache = '/tmp/verifier-go-cache'
    shutil.rmtree(cache, ignore_errors=True)
    os.makedirs(cache, mode=0o777)
    os.chmod(cache, 0o777)

    account = pwd.getpwnam('user')

    def demote():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['GOCACHE'] = cache
    result = subprocess.run(
        ['go', 'run', PACKER],
        cwd='/home/user',
        env=env,
        preexec_fn=demote,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'pack.go failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}'
    )


@pytest.fixture(scope='module', autouse=True)
def generated_archive():
    run_packer()


def test_backup_archive_exists_and_size():
    assert os.path.exists(ARCHIVE), f'Backup archive not found at {ARCHIVE}'
    assert os.path.isfile(ARCHIVE), f'{ARCHIVE} is not a file'

    size = os.path.getsize(ARCHIVE)
    threshold = 45000
    assert size < threshold, (
        f'Archive size {size} bytes is not strictly less than {threshold} bytes. '
        'You need to improve compression.'
    )


def parse_archive(data):
    assert len(data) >= 8, 'Archive is too short'
    assert data[:4] == b'CFGP', 'Archive has invalid magic bytes'
    count = struct.unpack_from('<I', data, 4)[0]
    assert count <= 10000, 'Archive declares an unreasonable file count'

    offset = 8
    entries = []
    for _ in range(count):
        assert offset + 2 <= len(data), 'Truncated path length'
        path_len = struct.unpack_from('<H', data, offset)[0]
        offset += 2
        assert offset + path_len + 8 <= len(data), 'Truncated archive header'
        path_bytes = data[offset:offset + path_len]
        offset += path_len
        try:
            path = path_bytes.decode('utf-8')
        except UnicodeDecodeError as exc:
            pytest.fail(f'Archive path is not UTF-8: {exc}')

        orig_size, comp_size = struct.unpack_from('<II', data, offset)
        offset += 8
        assert offset + comp_size <= len(data), 'Truncated compressed payload'
        compressed = data[offset:offset + comp_size]
        offset += comp_size

        inflater = zlib.decompressobj(-zlib.MAX_WBITS)
        try:
            payload = inflater.decompress(compressed) + inflater.flush()
        except zlib.error as exc:
            pytest.fail(f'Invalid raw DEFLATE payload for {path!r}: {exc}')
        assert inflater.eof, f'Incomplete DEFLATE stream for {path!r}'
        assert not inflater.unused_data, f'Extra bytes inside payload for {path!r}'
        assert len(payload) == orig_size, f'Uncompressed size mismatch for {path!r}'
        entries.append((path, payload))

    assert offset == len(data), 'Archive contains unparsed trailing data'
    return entries


def test_archive_contains_exact_filtered_files():
    with open(ARCHIVE, 'rb') as f:
        entries = parse_archive(f.read())

    actual = {}
    for path, payload in entries:
        name = os.path.basename(path)
        assert name, f'Archive contains an empty filename: {path!r}'
        assert name not in actual, f'Duplicate archived filename: {name}'
        actual[name] = payload

    expected = expected_files()
    assert set(actual) == set(expected), (
        f'Archived file set is incorrect. Missing: {sorted(set(expected) - set(actual))}; '
        f'unexpected: {sorted(set(actual) - set(expected))}'
    )
    for name, content in expected.items():
        assert actual[name] == content, f'Archived contents differ for {name}'


def test_backup_archive_extractable():
    shutil.rmtree(EXTRACT_DIR, ignore_errors=True)
    os.makedirs(EXTRACT_DIR)

    result = subprocess.run(
        [UNPACKER, ARCHIVE, EXTRACT_DIR],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        'config_unpacker failed to extract the archive.\n'
        f'STDOUT: {result.stdout}\nSTDERR: {result.stderr}'
    )

    extracted = {}
    for root, dirs, files in os.walk(EXTRACT_DIR):
        for filename in files:
            assert filename not in extracted, f'Duplicate extracted filename: {filename}'
            with open(os.path.join(root, filename), 'rb') as f:
                extracted[filename] = f.read()

    expected = expected_files()
    assert set(extracted) == set(expected), 'Extracted file set does not match the filtered files'
    for name, content in expected.items():
        assert extracted[name] == content, f'Extracted contents differ for {name}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
