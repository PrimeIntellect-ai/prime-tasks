#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pwd
import struct
import subprocess
import tempfile
import time
import uuid

import pytest

CPP_FILE = '/home/user/null_compressor.cpp'
EXE_FILE = '/home/user/null_compressor'
RAW_FILE = '/home/user/raw_data.bin'
ARCHIVE_FILE = '/home/user/compressed.archive'


def compress_null_rle(data: bytes) -> bytes:
    out = bytearray()
    i = 0
    n = len(data)
    while i < n:
        if data[i] == 0x00:
            count = 0
            while i < n and data[i] == 0x00 and count < 255:
                count += 1
                i += 1
            out.append(0xFF)
            out.append(count)
        elif data[i] == 0xFF:
            out.append(0xFF)
            out.append(0x00)
            i += 1
        else:
            out.append(data[i])
            i += 1
    return bytes(out)


def run_compressor(executable, data, output_path):
    tmp_path = output_path + '.tmp'
    for path in (output_path, tmp_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [executable, output_path],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'{executable} failed with status {result.returncode}: '
        f'{result.stderr.decode(errors="replace")}'
    )
    assert os.path.isfile(output_path), 'The requested output file was not created.'
    assert not os.path.exists(tmp_path), 'The .tmp file remained after successful completion.'
    with open(output_path, 'rb') as f:
        actual = f.read()
    assert actual == compress_null_rle(data)


@pytest.fixture(scope='session')
def rebuilt_executable():
    path = '/tmp/null_compressor_rebuilt_' + uuid.uuid4().hex
    result = subprocess.run(
        ['g++', '-O2', CPP_FILE, '-o', path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        'Submitted C++ source did not compile: ' + result.stderr.decode(errors='replace')
    )
    assert os.path.isfile(path) and os.access(path, os.X_OK)
    return path


def test_source_and_executable_exist():
    assert os.path.exists(CPP_FILE), f'Source code {CPP_FILE} is missing.'
    assert os.path.exists(EXE_FILE), f'Executable {EXE_FILE} is missing.'
    assert os.access(EXE_FILE, os.X_OK), f'File {EXE_FILE} is not executable.'
    assert os.path.isfile(CPP_FILE), f'{CPP_FILE} is not a regular file.'
    assert os.path.isfile(EXE_FILE), f'{EXE_FILE} is not a regular file.'
    with open(EXE_FILE, 'rb') as f:
        assert f.read(4) == bytes.fromhex('7f454c46'), 'The submitted executable is not an ELF binary.'


def test_tmp_file_does_not_exist():
    tmp_file = '/home/user/compressed.archive.tmp'
    assert not os.path.exists(tmp_file), f'Temporary file {tmp_file} should have been renamed or deleted.'


def test_compressed_archive_content():
    assert os.path.exists(RAW_FILE), f'Raw data file {RAW_FILE} is missing.'
    assert os.path.exists(ARCHIVE_FILE), f'Compressed archive {ARCHIVE_FILE} is missing.'

    with open(RAW_FILE, 'rb') as f:
        raw_data = f.read()
    expected_data = compress_null_rle(raw_data)

    with open(ARCHIVE_FILE, 'rb') as f:
        actual_data = f.read()
    assert actual_data == expected_data, 'The contents of the compressed archive do not match the expected Null-Byte RLE output.'


def test_argument_validation():
    work = tempfile.mkdtemp(prefix='null_rle_args_', dir='/home/user')
    first = os.path.join(work, 'first.archive')
    second = os.path.join(work, 'second.archive')

    no_arg = subprocess.run([EXE_FILE], input=b'abc', stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert no_arg.returncode != 0, 'The utility must reject invocation without an output argument.'

    too_many = subprocess.run([EXE_FILE, first, second], input=b'abc', stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert too_many.returncode != 0, 'The utility must reject more than one output argument.'
    assert not os.path.exists(first) and not os.path.exists(first + '.tmp')

    relative_name = 'relative_' + uuid.uuid4().hex + '.archive'
    relative = subprocess.run(
        [EXE_FILE, relative_name], input=b'abc', cwd=work,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
    )
    assert relative.returncode != 0, 'The output argument must be an absolute path.'
    assert not os.path.exists(os.path.join(work, relative_name))
    assert not os.path.exists(os.path.join(work, relative_name + '.tmp'))


@pytest.mark.parametrize('which', ['submitted', 'rebuilt'])
def test_stdin_and_rle_on_independent_inputs(which, rebuilt_executable):
    executable = EXE_FILE if which == 'submitted' else rebuilt_executable
    with open(RAW_FILE, 'rb') as f:
        supplied_raw = f.read()

    cases = [
        b'',
        b'plain binary data\n',
        bytes(range(256)),
        b'\xff\x00\xff\x00\x00\xff',
        b'A' + b'\x00' * 254 + b'B',
        b'A' + b'\x00' * 255 + b'B',
        b'A' + b'\x00' * 256 + b'B',
        b'A' + b'\x00' * 510 + b'B',
        os.urandom(4096) + b'\x00' * 300 + os.urandom(257),
        supplied_raw,
    ]

    base = tempfile.mkdtemp(prefix='null_rle_behavior_', dir='/home/user')
    for index, data in enumerate(cases):
        run_compressor(executable, data, os.path.join(base, f'case_{index}.archive'))


def atomic_run(executable):
    directory = tempfile.mkdtemp(prefix='null_rle_atomic_', dir='/home/user')
    os.chmod(directory, 0o777)
    target = os.path.join(directory, 'result.archive')
    tmp_name = 'result.archive.tmp'
    target_name = 'result.archive'

    old_data = b'preexisting destination must remain independently replaceable'
    with open(target, 'wb') as f:
        f.write(old_data)
    os.chown(target, 0, 0)
    os.chmod(target, 0o444)
    old_inode = os.stat(target).st_ino

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = os.O_NONBLOCK
    IN_OPEN = 0x00000020
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    fd = inotify_init1(IN_NONBLOCK)
    assert fd >= 0, 'Could not initialize inotify.'
    watch = inotify_add_watch(fd, directory.encode(), IN_OPEN | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE)
    assert watch >= 0, 'Could not watch the output directory.'

    user = pwd.getpwnam('user')
    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    data = os.urandom(1024 * 1024) + b'\x00' * 600 + b'\xffEND'
    result = subprocess.run(
        [executable, target], input=data,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20, preexec_fn=demote,
    )
    time.sleep(0.05)

    raw_events = bytearray()
    while True:
        try:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            raw_events.extend(chunk)
        except BlockingIOError:
            break
    os.close(fd)

    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert not os.path.exists(target + '.tmp'), 'Temporary file was not renamed away.'
    with open(target, 'rb') as f:
        assert f.read() == compress_null_rle(data)
    assert os.stat(target).st_ino != old_inode, 'The destination was modified in place instead of atomically replaced.'

    events = []
    offset = 0
    while offset + 16 <= len(raw_events):
        wd, mask, cookie, name_len = struct.unpack_from('iIII', raw_events, offset)
        offset += 16
        name_bytes = bytes(raw_events[offset:offset + name_len])
        offset += name_len
        name = name_bytes.split(b'\0', 1)[0].decode(errors='replace')
        events.append((mask, cookie, name))

    assert any(name == tmp_name and (mask & IN_OPEN) for mask, cookie, name in events), \
        'The required <output>.tmp file was not opened.'
    moved_from = {cookie for mask, cookie, name in events if name == tmp_name and (mask & IN_MOVED_FROM) and cookie}
    moved_to = {cookie for mask, cookie, name in events if name == target_name and (mask & IN_MOVED_TO) and cookie}
    assert moved_from & moved_to, 'The .tmp file was not atomically renamed to the requested destination.'


@pytest.mark.parametrize('which', ['submitted', 'rebuilt'])
def test_atomic_tmp_and_rename_semantics(which, rebuilt_executable):
    atomic_run(EXE_FILE if which == 'submitted' else rebuilt_executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
