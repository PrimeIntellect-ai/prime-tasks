#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_task.py
import hashlib
import io
import os
import re
import shutil
import stat
import struct
import subprocess
import tarfile
import tempfile

BACKUPS = '/app/storage/backups.tar'
WAL_DIR = '/home/user/wal_clean'
ELF_DIR = '/home/user/elf_backup'
TARGET = 'VOL-84B'


def digest(data):
    return hashlib.sha256(data).digest()


def compact(data):
    assert len(data) >= 8, 'Source WAL is shorter than its header'
    assert data[:4] == b'WAL\0', 'Source WAL has invalid magic'
    out = bytearray(data[:8])
    pos = 8
    while pos < len(data):
        assert pos + 5 <= len(data), 'Truncated source WAL record header'
        record_type = data[pos]
        length = struct.unpack_from('<I', data, pos + 1)[0]
        end = pos + 5 + length
        assert end <= len(data), 'Truncated source WAL payload'
        if record_type != 3:
            out.extend(data[pos:end])
        pos = end
    return bytes(out)


def load_target_files():
    with tarfile.open(BACKUPS, 'r') as outer:
        matches = [m for m in outer.getmembers()
                   if m.isfile() and os.path.basename(m.name) == TARGET + '.tar.gz']
        assert len(matches) == 1, 'Target volume archive is missing or ambiguous'
        stream = outer.extractfile(matches[0])
        assert stream is not None
        archive_data = stream.read()

    files = []
    with tarfile.open(fileobj=io.BytesIO(archive_data), mode='r:gz') as inner:
        for member in inner.getmembers():
            if member.isfile():
                stream = inner.extractfile(member)
                assert stream is not None
                files.append((member.name, stream.read()))
    return files


def regular_directory_files(path):
    assert os.path.exists(path), f'Directory {path} does not exist.'
    assert os.path.isdir(path), f'{path} is not a directory.'
    names = os.listdir(path)
    result = []
    for name in names:
        full = os.path.join(path, name)
        info = os.lstat(full)
        assert stat.S_ISREG(info.st_mode), f'{full} is not a regular file'
        result.append((name, full))
    return result


def find_c_sources():
    found = []
    seen = set()
    for root in ('/home/user', '/app', '/root', '/tmp'):
        if not os.path.isdir(root):
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {'.git', '__pycache__', 'node_modules'}]
            for name in files:
                if not name.endswith('.c'):
                    continue
                path = os.path.join(base, name)
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    real = os.path.realpath(path)
                    if real not in seen:
                        seen.add(real)
                        found.append(real)
                except OSError:
                    pass
    found.sort(key=lambda p: (0 if 'compact' in os.path.basename(p).lower() else 1, p))
    return found


def exercise_c_implementation():
    sources = find_c_sources()
    assert sources, 'No C source implementation was found'

    records = [
        (1, os.urandom(17)),
        (3, os.urandom(31)),
        (2, b''),
        (1, os.urandom(257)),
        (3, b''),
        (2, os.urandom(9)),
    ]
    fixture = bytearray(b'WAL\0' + struct.pack('<I', 0x51A7C39D))
    expected = bytearray(fixture)
    for record_type, payload in records:
        encoded = bytes([record_type]) + struct.pack('<I', len(payload)) + payload
        fixture.extend(encoded)
        if record_type != 3:
            expected.extend(encoded)

    errors = []
    for source in sources:
        with tempfile.TemporaryDirectory(prefix='wal_c_test_') as td:
            executable = os.path.join(td, 'compact_wal_test')
            compiled = subprocess.run(
                ['gcc', '-std=c11', '-O2', source, '-o', executable],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            if compiled.returncode != 0:
                errors.append(f'{source}: compilation failed')
                continue

            input_path = os.path.join(td, 'input.wal')
            output_path = os.path.join(td, 'output.wal')
            with open(input_path, 'wb') as handle:
                handle.write(fixture)
            try:
                run = subprocess.run(
                    [executable, input_path, output_path], cwd=td,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            except subprocess.TimeoutExpired:
                errors.append(f'{source}: execution timed out')
                continue

            if run.returncode == 0 and os.path.isfile(output_path):
                with open(output_path, 'rb') as handle:
                    actual = handle.read()
                if actual == bytes(expected):
                    return
            errors.append(f'{source}: did not correctly compact a generated WAL fixture')

    raise AssertionError('No submitted C program passed compilation and behavioral testing. ' + '; '.join(errors[:5]))


source_files = load_target_files()
source_wals = [data for _, data in source_files if data.startswith(b'WAL\0')]
source_elfs = [data for _, data in source_files if data.startswith(b'\x7fELF')]
assert len(source_wals) == 10, 'Unexpected target WAL source count'
assert len(source_elfs) == 5, 'Unexpected target ELF source count'

# Execute the requested C artifact on an independently generated input.
exercise_c_implementation()

wal_files = regular_directory_files(WAL_DIR)
expected_wal_names = [f'clean_{i:03d}.wal' for i in range(1, len(source_wals) + 1)]
assert sorted(name for name, _ in wal_files) == expected_wal_names, \
    'WAL output filenames or file count are incorrect'

actual_wals = []
for _, path in wal_files:
    with open(path, 'rb') as handle:
        data = handle.read()
    assert data.startswith(b'WAL\0'), f'{path} is not a WAL file'
    # Parsing the result also rejects malformed/truncated records.
    assert compact(data) == data, f'{path} still contains Debug records or is malformed'
    actual_wals.append(digest(data))

expected_wals = [digest(compact(data)) for data in source_wals]
assert sorted(actual_wals) == sorted(expected_wals), \
    'Compacted WAL contents do not match the target volume records'

elf_files = regular_directory_files(ELF_DIR)
expected_elf_names = [f'elf_{i:03d}.bin' for i in range(1, len(source_elfs) + 1)]
assert sorted(name for name, _ in elf_files) == expected_elf_names, \
    'ELF output filenames or file count are incorrect'
actual_elfs = []
for _, path in elf_files:
    with open(path, 'rb') as handle:
        data = handle.read()
    assert data.startswith(b'\x7fELF'), f'{path} is not an ELF file'
    actual_elfs.append(digest(data))
assert sorted(actual_elfs) == sorted(digest(data) for data in source_elfs), \
    'ELF outputs do not match the target volume executables'

# Preserve the original final metric assertion.
total_size = sum(os.path.getsize(path) for _, path in wal_files)
expected_size = 34580
assert total_size == expected_size, (
    f'Metric mismatch: Total size of files in {WAL_DIR} is {total_size} bytes, '
    f'but expected exactly {expected_size} bytes.'
)
PY

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
