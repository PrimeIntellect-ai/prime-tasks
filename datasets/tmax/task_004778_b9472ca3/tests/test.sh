#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/stream_guard
cat << 'GUARD_EOF' > /tmp/stream_guard/sitecustomize.py
import builtins
import io
import os

_ALLOWED_OUTPUT = os.path.realpath('/home/user/filtered_backup.fc')
_original_open = builtins.open
_original_io_open = io.open
_original_os_open = os.open

def _is_write_mode(mode):
    return any(flag in mode for flag in ('w', 'a', 'x', '+'))

def _check_path(path):
    if isinstance(path, int):
        return
    if os.path.realpath(os.fspath(path)) != _ALLOWED_OUTPUT:
        raise RuntimeError('Optimized script attempted to write an intermediate file: %r' % (path,))

def guarded_open(file, mode='r', *args, **kwargs):
    if _is_write_mode(mode):
        _check_path(file)
    return _original_open(file, mode, *args, **kwargs)

def guarded_io_open(file, mode='r', *args, **kwargs):
    if _is_write_mode(mode):
        _check_path(file)
    return _original_io_open(file, mode, *args, **kwargs)

def guarded_os_open(path, flags, mode=0o777, *, dir_fd=None):
    write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
    if flags & write_flags:
        _check_path(path)
    return _original_os_open(path, flags, mode, dir_fd=dir_fd)

builtins.open = guarded_open
io.open = guarded_io_open
os.open = guarded_os_open
GUARD_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import json
import os
import subprocess
import sys
import tarfile
import time
import zipfile
import zlib

import pytest

AGENT_PATH = '/home/user/fast_extract.py'
BASELINE_PATH = '/home/user/baseline.py'
ARCHIVE_PATH = '/home/user/data/daily_backup.tar'
OUTPUT_PATH = '/home/user/filtered_backup.fc'


def test_fast_extract_exists():
    path = AGENT_PATH
    assert os.path.isfile(path), f'Expected optimized script missing at {path}'


def test_script_uses_chunkwriter_and_no_extraction_apis():
    with open(AGENT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=AGENT_PATH)

    chunkwriter_names = {'ChunkWriter'}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith('fastchunker'):
            for alias in node.names:
                if alias.name == 'ChunkWriter':
                    chunkwriter_names.add(alias.asname or alias.name)

    uses_chunkwriter = any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id in chunkwriter_names) or
            (isinstance(node.func, ast.Attribute) and node.func.attr == 'ChunkWriter')
        )
        for node in ast.walk(tree)
    )
    assert uses_chunkwriter, 'The optimized script must use fastchunker.ChunkWriter'

    forbidden = [
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {'extract', 'extractall'}
    ]
    assert not forbidden, 'The optimized script must not extract tar/zip members to disk'


def expected_chunks():
    expected = []
    with tarfile.open(ARCHIVE_PATH, 'r') as tar:
        members = [m for m in tar.getmembers() if m.isfile() and m.name.endswith('.zip')]
        assert len(members) == 200, f'Input archive should contain 200 zip members, found {len(members)}'

        for member in members:
            member_file = tar.extractfile(member)
            assert member_file is not None
            with zipfile.ZipFile(io.BytesIO(member_file.read()), 'r') as zf:
                info = json.loads(zf.read('info.json').decode('utf-8'))
                lines = zf.read('trace.log').decode('utf-8').splitlines(keepends=True)

            errors = []
            in_error = False
            for line in lines:
                if line.startswith('[ERROR]'):
                    in_error = True
                    errors.append(line)
                elif line.startswith('[INFO]') or line.startswith('[WARN]'):
                    in_error = False
                elif in_error:
                    errors.append(line)

            expected.append(f"SERVER_ID: {info['server_id']}\n{''.join(errors)}\n---\n")
    return expected


def decode_all_chunks(path):
    with open(path, 'rb') as f:
        remaining = f.read()
    assert remaining, 'Output archive is empty'

    decoded = []
    while remaining:
        before = len(remaining)
        decoder = zlib.decompressobj()
        try:
            payload = decoder.decompress(remaining)
            payload += decoder.flush()
        except zlib.error as exc:
            pytest.fail(f'Output contains an invalid compressed chunk: {exc}')
        assert decoder.eof, 'Output contains a truncated compressed chunk'
        remaining = decoder.unused_data
        assert len(remaining) < before, 'Decoder made no progress while reading output'
        try:
            decoded.append(payload.decode('utf-8'))
        except UnicodeDecodeError as exc:
            pytest.fail(f'Output chunk is not valid UTF-8: {exc}')
    return decoded


def test_speedup_and_correctness():
    baseline_path = BASELINE_PATH
    agent_path = AGENT_PATH
    output_path = OUTPUT_PATH

    assert os.path.isfile(baseline_path), f'Baseline script missing at {baseline_path}'
    assert os.path.isfile(agent_path), f'Agent script missing at {agent_path}'
    with open(baseline_path, 'rb') as f:
        baseline_source = f.read()
    with open(agent_path, 'rb') as f:
        agent_source = f.read()
    assert agent_source != baseline_source, 'Optimized script must not be a byte-identical copy of the baseline'

    if os.path.exists(output_path):
        os.remove(output_path)

    t0 = time.time()
    try:
        subprocess.run([sys.executable, baseline_path], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Baseline script failed to run:\n{e.stderr}')
    base_time = time.time() - t0

    assert os.path.exists(output_path), 'Baseline script did not create the output file'
    os.remove(output_path)

    expected = expected_chunks()

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = '/tmp/stream_guard' + (os.pathsep + old_pythonpath if old_pythonpath else '')

    t1 = time.time()
    try:
        subprocess.run([sys.executable, agent_path], check=True, capture_output=True, text=True, env=env)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Agent script failed to run:\n{e.stderr}')
    agent_time = time.time() - t1

    assert agent_time > 0, 'Agent script executed in 0 seconds, which is invalid.'
    speedup = base_time / agent_time
    assert speedup >= 3.0, f'Speedup {speedup:.2f}x is less than the 3.0x threshold (Base: {base_time:.2f}s, Agent: {agent_time:.2f}s)'

    assert os.path.exists(output_path), f'Agent script did not create the output file at {output_path}'

    try:
        import fastchunker
    except ImportError:
        pytest.fail("Failed to import 'fastchunker'. Ensure the package is fixed and installed in the environment.")

    try:
        reader = fastchunker.ChunkReader(output_path)
        data = reader.read_all()
    except Exception as e:
        pytest.fail(f'Failed to read output file with fastchunker.ChunkReader: {e}')

    assert 'SERVER_ID: srv_0' in data, "Output data is missing expected 'SERVER_ID: srv_0' content."
    assert '[ERROR]' in data, "Output data is missing expected '[ERROR]' log content."

    actual = decode_all_chunks(output_path)
    assert len(actual) == len(expected), f'Expected {len(expected)} server chunks, found {len(actual)}'
    assert actual == expected, 'Output chunks do not exactly match the filtered server data in archive order'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
