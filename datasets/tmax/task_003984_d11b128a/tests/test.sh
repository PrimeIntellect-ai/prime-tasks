#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import struct
import threading
import time

import pytest
import requests

URL = 'http://127.0.0.1:8000/restore'
GOOD_KEY = 'Z9xQ2mP4'


def make_archive(path, key, entries):
    with open(path, 'wb') as f:
        f.write(b'BKP1')
        f.write(key.encode('ascii')[:8].ljust(8, b' '))
        for entry_path, entry_data in entries:
            path_bytes = entry_path.encode('utf-8')
            f.write(struct.pack('<H', len(path_bytes)))
            f.write(path_bytes)
            f.write(struct.pack('<I', len(entry_data)))
            f.write(entry_data)


def post_restore(archive, target, timeout=15):
    try:
        return requests.post(URL, json={
            'archive': os.path.abspath(archive),
            'target': os.path.abspath(target),
        }, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to the extraction service: {exc}')


def parse_json(resp):
    try:
        return resp.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {resp.text}')


def test_invalid_key_uses_archive_contents(tmp_path):
    archive = tmp_path / f'{secrets.token_hex(9)}.bkp'
    target = tmp_path / f'target_{secrets.token_hex(7)}'
    wrong_key = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(8))
    if wrong_key == GOOD_KEY:
        wrong_key = 'WRONGKEY'
    make_archive(archive, wrong_key, [(f'{secrets.token_hex(5)}.dat', os.urandom(37))])

    resp = post_restore(archive, target)
    assert resp.status_code == 403, (
        f'Expected HTTP 403 for invalid key, got {resp.status_code}. Response: {resp.text}'
    )
    assert parse_json(resp) == {'error': 'invalid key'}
    assert not target.exists() or not any(target.rglob('*')), 'Invalid-key archive was extracted'


def test_valid_extraction_contents_and_zip_slip(tmp_path):
    archive = tmp_path / f'{secrets.token_hex(10)}.bkp'
    target = tmp_path / f'restore_{secrets.token_hex(8)}'
    parent_escape = f'escape_{secrets.token_hex(8)}.bin'
    absolute_escape = f'/tmp/absolute_{secrets.token_hex(8)}.bin'
    data1 = os.urandom(4097)
    data2 = os.urandom(8195)
    bad1 = os.urandom(43)
    bad2 = os.urandom(47)

    make_archive(archive, GOOD_KEY, [
        ('valid/file1.txt', data1),
        (f'../{parent_escape}', bad1),
        (absolute_escape, bad2),
        ('deep/dir/file2.txt', data2),
    ])

    resp = post_restore(archive, target)
    assert resp.status_code == 200, (
        f'Expected HTTP 200 for valid extraction, got {resp.status_code}. Response: {resp.text}'
    )
    result = parse_json(resp)
    assert result.get('extracted') == 2, f"Expected 2 extracted files, got {result.get('extracted')}"
    assert result.get('skipped') == 2, f"Expected 2 skipped files, got {result.get('skipped')}"

    file1 = target / 'valid/file1.txt'
    file2 = target / 'deep/dir/file2.txt'
    assert file1.exists(), "Valid file 'valid/file1.txt' was not extracted."
    assert file2.exists(), "Valid file 'deep/dir/file2.txt' was not extracted."
    assert file1.read_bytes() == data1, 'First extracted file has incorrect contents'
    assert file2.read_bytes() == data2, 'Second extracted file has incorrect contents'

    assert not (target.parent / parent_escape).exists(), "Zip Slip attack succeeded: '../escape' was extracted."
    assert not os.path.exists(absolute_escape), "Zip Slip attack succeeded: absolute path was extracted."
    assert not list(target.rglob('*.tmp')), 'Temporary extraction files were left behind'


def test_atomic_temporary_file_and_rename(tmp_path):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f'inotify_init1 failed with errno {ctypes.get_errno()}'

    target = tmp_path / f'atomic_target_{secrets.token_hex(7)}'
    target.mkdir()
    watch = libc.inotify_add_watch(fd, os.fsencode(target), IN_CREATE | IN_MOVED_TO)
    assert watch >= 0, f'inotify_add_watch failed with errno {ctypes.get_errno()}'

    filename = f'payload_{secrets.token_hex(10)}.bin'
    payload = os.urandom(16 * 1024 * 1024 + 113)
    archive = tmp_path / f'{secrets.token_hex(11)}.bkp'
    make_archive(archive, GOOD_KEY, [(filename, payload)])

    try:
        resp = post_restore(archive, target, timeout=30)
        assert resp.status_code == 200, f'Atomic extraction request failed: {resp.status_code} {resp.text}'
        result = parse_json(resp)
        assert result.get('extracted') == 1
        assert result.get('skipped') == 0

        events = []
        deadline = time.time() + 2
        while time.time() < deadline:
            try:
                block = os.read(fd, 65536)
            except BlockingIOError:
                time.sleep(0.01)
                continue
            offset = 0
            while offset + 16 <= len(block):
                _, mask, _, name_len = struct.unpack_from('=iIII', block, offset)
                offset += 16
                raw_name = block[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b'\0', 1)[0].decode('utf-8', 'surrogateescape')
                events.append((mask, name))

        assert any(mask & IN_CREATE and name == filename + '.tmp' for mask, name in events), (
            'The required <file>.tmp temporary file was not created'
        )
        assert any(mask & IN_MOVED_TO and name == filename for mask, name in events), (
            'The completed temporary file was not atomically renamed to its final name'
        )
        output = target / filename
        assert output.read_bytes() == payload, 'Atomically extracted file has incorrect contents'
        assert not (target / (filename + '.tmp')).exists(), 'Temporary file remains after extraction'
    finally:
        os.close(fd)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
