#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import stat
import struct
import subprocess
import tempfile
import time
import pytest

MAGIC = b'\xde\xad\xbe\xef'
CHUNK = 51200


def get_expected_files(base_dir):
    expected_files = {}
    for root, dirs, files in os.walk(base_dir, followlinks=False):
        if os.path.islink(root):
            continue
        for name in files:
            full_path = os.path.join(root, name)
            if os.path.isfile(full_path) and not os.path.islink(full_path):
                rel_path = os.path.relpath(full_path, base_dir)
                with open(full_path, 'rb') as fp:
                    expected_files[rel_path] = fp.read()
    return expected_files


def parse_archive(archive_path):
    if not os.path.exists(archive_path):
        return {}

    files_data = {}
    with open(archive_path, 'rb') as f:
        while True:
            magic = f.read(4)
            if not magic:
                break
            if magic != MAGIC:
                raise ValueError("Invalid magic bytes found in archive.")

            path_len_data = f.read(2)
            if len(path_len_data) < 2:
                break
            path_len = struct.unpack('>H', path_len_data)[0]

            path_bytes = f.read(path_len)
            if len(path_bytes) < path_len:
                break
            path = path_bytes.decode('utf-8', errors='replace')

            chunk_idx_data = f.read(4)
            if len(chunk_idx_data) < 4:
                break
            chunk_idx = struct.unpack('>I', chunk_idx_data)[0]

            data_len_data = f.read(4)
            if len(data_len_data) < 4:
                break
            data_len = struct.unpack('>I', data_len_data)[0]

            payload = f.read(data_len)
            if len(payload) < data_len:
                break

            if path not in files_data:
                files_data[path] = {}
            files_data[path][chunk_idx] = payload

    reconstructed = {}
    for path, chunks in files_data.items():
        if not chunks:
            continue
        max_chunk = max(chunks.keys())
        if set(chunks.keys()) != set(range(max_chunk + 1)):
            continue
        reconstructed[path] = b''.join(chunks[i] for i in range(max_chunk + 1))
    return reconstructed


def test_archive_f1_score():
    base_dir = "/home/user/artifacts"
    archive_path = "/home/user/repository.bin"

    assert os.path.exists(archive_path), f"Archive file {archive_path} does not exist."
    expected_files = get_expected_files(base_dir)

    try:
        archived_files = parse_archive(archive_path)
    except ValueError as e:
        pytest.fail(f"Failed to parse archive: {e}")

    correctly_archived = 0
    for path, content in archived_files.items():
        for exp_path, exp_content in expected_files.items():
            if exp_path == path or exp_path.endswith(path) or path.endswith(exp_path):
                if content == exp_content:
                    correctly_archived += 1
                    break

    total_expected = len(expected_files)
    total_archived = len(archived_files)
    precision = 0.0 if total_archived == 0 else correctly_archived / total_archived
    recall = (1.0 if total_archived == 0 else 0.0) if total_expected == 0 else correctly_archived / total_expected
    f1_score = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)

    assert f1_score >= 1.0, f"F1 score is {f1_score}, expected >= 1.0. Precision: {precision}, Recall: {recall}. Correct: {correctly_archived}, Expected: {total_expected}, Archived: {total_archived}."


def encode_record(path, index, payload):
    path_bytes = path.encode('utf-8')
    return (MAGIC + struct.pack('>H', len(path_bytes)) + path_bytes +
            struct.pack('>I', index) + struct.pack('>I', len(payload)) + payload)


def parse_records(data):
    records = []
    pos = 0
    while pos < len(data):
        assert data[pos:pos + 4] == MAGIC, f"invalid magic at offset {pos}"
        pos += 4
        assert pos + 2 <= len(data), "truncated path length"
        path_len = struct.unpack('>H', data[pos:pos + 2])[0]
        pos += 2
        assert pos + path_len + 8 <= len(data), "truncated record header"
        path_bytes = data[pos:pos + path_len]
        pos += path_len
        path = path_bytes.decode('utf-8')
        index = struct.unpack('>I', data[pos:pos + 4])[0]
        pos += 4
        data_len = struct.unpack('>I', data[pos:pos + 4])[0]
        pos += 4
        assert data_len <= CHUNK, f"chunk for {path} exceeds 50 KB"
        assert pos + data_len <= len(data), "truncated payload"
        payload = data[pos:pos + data_len]
        pos += data_len
        records.append((path, index, payload))
    return records


def create_fixture(base):
    os.makedirs(os.path.join(base, 'nested', 'deeper'))
    expected = {
        'small.bin': os.urandom(137),
        'large.bin': os.urandom(120 * 1024),
        'nested/deeper/boundary.bin': os.urandom(CHUNK + 1),
    }
    for rel, content in expected.items():
        path = os.path.join(base, *rel.split('/'))
        with open(path, 'wb') as f:
            f.write(content)
    os.symlink(base, os.path.join(base, 'nested', 'deeper', 'ancestor_loop'))
    return expected


def assert_exact_archive(records, expected, seed=None):
    chunks = {}
    for path, index, payload in records:
        if seed is not None and (path, index, payload) == seed:
            continue
        assert path in expected, f"unexpected archived path: {path}"
        assert not os.path.isabs(path) and path == os.path.normpath(path)
        key = (path, index)
        assert key not in chunks, f"duplicate chunk {key}"
        chunks[key] = payload

    expected_record_count = 0
    for path, content in expected.items():
        count = max(1, (len(content) + CHUNK - 1) // CHUNK)
        expected_record_count += count
        indices = sorted(index for candidate, index in chunks if candidate == path)
        assert indices == list(range(count)), f"wrong chunk indices for {path}: {indices}"
        for index in range(count):
            assert chunks[(path, index)] == content[index * CHUNK:(index + 1) * CHUNK]
    assert len(chunks) == expected_record_count
    return expected_record_count


def build_flock_probe(directory):
    source = os.path.join(directory, 'flock_probe.c')
    library = os.path.join(directory, 'flock_probe.so')
    with open(source, 'w') as f:
        f.write(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#include <stdlib.h>
int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = 0;
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    int result = real_flock(fd, operation);
    if (result == 0) {
        const char *log = getenv("FLOCK_PROBE_LOG");
        if (log) {
            int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (out >= 0) {
                char c = (operation & LOCK_UN) ? 'U' : ((operation & LOCK_EX) ? 'X' : 'O');
                write(out, &c, 1);
                close(out);
            }
        }
    }
    return result;
}
''')
    subprocess.run(['gcc', '-shared', '-fPIC', source, '-o', library, '-ldl'], check=True)
    return library


def test_program_source_execution_chunking_cycles_and_locking():
    source = '/home/user/safe_packer.c'
    binary = '/home/user/safe_packer'
    assert os.path.isfile(source), f"missing C source: {source}"
    assert os.path.getsize(source) > 0, "C source is empty"
    assert os.path.isfile(binary), f"missing compiled program: {binary}"
    assert os.access(binary, os.X_OK), "compiled program is not executable"
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "safe_packer is not a compiled ELF executable"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'safe_packer.rebuilt')
        subprocess.run(['gcc', '-O2', source, '-o', rebuilt], check=True, timeout=20)

        fixture = os.path.join(td, 'fixture')
        expected = create_fixture(fixture)
        archive = os.path.join(td, 'archive.bin')
        seed_tuple = ('__existing_metadata__', 0, b'keep')
        prefix = encode_record(*seed_tuple)
        with open(archive, 'wb') as f:
            f.write(prefix)

        probe_log = os.path.join(td, 'flock.log')
        probe = build_flock_probe(td)
        env = os.environ.copy()
        env['LD_PRELOAD'] = probe
        env['FLOCK_PROBE_LOG'] = probe_log

        with open(archive, 'r+b') as locked:
            fcntl.flock(locked.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen([binary, fixture, archive], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(0.5)
            assert proc.poll() is None, "packer did not wait for the archive's exclusive lock"
            locked.seek(0)
            assert locked.read() == prefix, "packer wrote or replaced data without acquiring the lock"
            fcntl.flock(locked.fileno(), fcntl.LOCK_UN)

        try:
            stdout, stderr = proc.communicate(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail("packer did not terminate; symlink cycle detection failed")
        assert proc.returncode == 0, f"packer failed: {stderr.decode(errors='replace')}"

        with open(archive, 'rb') as f:
            packed = f.read()
        assert packed.startswith(prefix), "packer did not append to the existing archive"
        record_count = assert_exact_archive(parse_records(packed), expected, seed_tuple)

        with open(probe_log, 'r') as f:
            lock_events = f.read()
        assert lock_events == 'XU' * record_count, (
            "each complete chunk record must have its own successful exclusive flock/unlock pair"
        )

        second_archive = os.path.join(td, 'rebuilt.bin')
        completed = subprocess.run([rebuilt, fixture, second_archive], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=8)
        assert completed.returncode == 0, completed.stderr.decode(errors='replace')
        with open(second_archive, 'rb') as f:
            assert_exact_archive(parse_records(f.read()), expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
