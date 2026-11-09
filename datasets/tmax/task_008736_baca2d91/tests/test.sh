#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest


def get_config():
    config_path = '/home/user/chunk_config.ini'
    assert os.path.exists(config_path), f"Config file missing at {config_path}"

    config = {}
    with open(config_path, 'r') as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                config[k.strip()] = v.strip()

    assert 'max_chunk_size' in config, "max_chunk_size missing from config"
    assert 'output_dir' in config, "output_dir missing from config"

    return int(config['max_chunk_size']), config['output_dir']


def get_records():
    dump_path = '/home/user/project_dump.bin'
    assert os.path.exists(dump_path), f"Binary dump missing at {dump_path}"

    records = []
    with open(dump_path, 'rb') as f:
        while True:
            length_bytes = f.read(4)
            if not length_bytes:
                break
            assert len(length_bytes) == 4, "Incomplete length prefix in binary dump"
            length = struct.unpack('<I', length_bytes)[0]

            data = f.read(length)
            assert len(data) == length, "Incomplete record data in binary dump"

            text = data.decode('utf-16le')
            utf8_data = text.encode('utf-8')
            records.append(utf8_data)

    return records


def expected_chunks(records, max_chunk_size):
    chunks = []
    current = []
    current_size = 0
    for rec in records:
        if current and current_size + len(rec) > max_chunk_size:
            chunks.append(current)
            current = [rec]
            current_size = len(rec)
        else:
            current.append(rec)
            current_size += len(rec)
    if current:
        chunks.append(current)
    return chunks


def assert_outputs(output_dir, records, max_chunk_size):
    chunks = expected_chunks(records, max_chunk_size)
    assert os.path.isdir(output_dir), f"Output directory missing: {output_dir}"

    expected_index_lines = []
    for i, chunk_records in enumerate(chunks, start=1):
        name = f"chunk_{i:03d}.log"
        path = os.path.join(output_dir, name)
        assert os.path.exists(path), f"Expected chunk file missing: {path}"
        with open(path, 'rb') as f:
            actual = f.read()
        assert actual == b''.join(chunk_records), f"Content mismatch in {name}"
        expected_index_lines.append(f"{name},{len(chunk_records)}")

    index_path = os.path.join(output_dir, 'index.txt')
    assert os.path.exists(index_path), f"Index file missing: {index_path}"
    with open(index_path, 'r') as f:
        actual_index_lines = [line.strip() for line in f if line.strip()]
    assert actual_index_lines == expected_index_lines, (
        f"Index file content mismatch. Expected {expected_index_lines}, got {actual_index_lines}"
    )

    actual_files = set(os.listdir(output_dir))
    expected_files = {f"chunk_{i:03d}.log" for i in range(1, len(chunks) + 1)}
    expected_files.add('index.txt')
    unexpected_files = actual_files - expected_files
    assert not unexpected_files, f"Found unexpected files in output directory: {unexpected_files}"


def test_final_state():
    max_chunk_size, output_dir = get_config()
    records = get_records()

    expected_chunks_list = []
    current_chunk_records = []
    current_chunk_size = 0

    for rec in records:
        rec_len = len(rec)
        if current_chunk_size + rec_len > max_chunk_size and current_chunk_records:
            expected_chunks_list.append(current_chunk_records)
            current_chunk_records = [rec]
            current_chunk_size = rec_len
        else:
            current_chunk_records.append(rec)
            current_chunk_size += rec_len

    if current_chunk_records:
        expected_chunks_list.append(current_chunk_records)

    assert os.path.isdir(output_dir), f"Output directory missing: {output_dir}"

    expected_index_lines = []

    for i, chunk_records in enumerate(expected_chunks_list, start=1):
        chunk_filename = f"chunk_{i:03d}.log"
        chunk_path = os.path.join(output_dir, chunk_filename)

        assert os.path.exists(chunk_path), f"Expected chunk file missing: {chunk_path}"

        with open(chunk_path, 'rb') as f:
            actual_data = f.read()

        expected_data = b''.join(chunk_records)
        assert actual_data == expected_data, f"Content mismatch in {chunk_filename}"

        expected_index_lines.append(f"{chunk_filename},{len(chunk_records)}")

    index_path = os.path.join(output_dir, 'index.txt')
    assert os.path.exists(index_path), f"Index file missing: {index_path}"

    with open(index_path, 'r') as f:
        actual_index_lines = [line.strip() for line in f if line.strip()]

    assert actual_index_lines == expected_index_lines, f"Index file content mismatch. Expected {expected_index_lines}, got {actual_index_lines}"

    actual_files = set(os.listdir(output_dir))
    expected_files = {f"chunk_{i:03d}.log" for i in range(1, len(expected_chunks_list) + 1)}
    expected_files.add("index.txt")

    unexpected_files = actual_files - expected_files
    assert not unexpected_files, f"Found unexpected files in output directory: {unexpected_files}"


def test_cpp_utility_exists_compiles_and_runs():
    home = Path('/home/user')
    source_suffixes = {'.cpp', '.cc', '.cxx', '.c++'}
    sources = sorted(
        p for p in home.rglob('*')
        if p.is_file() and p.suffix.lower() in source_suffixes
    )
    assert sources, "No C++ source file was submitted under /home/user"

    # Capture pre-existing executables before the verifier compiles anything.
    executables = []
    for p in home.rglob('*'):
        if not p.is_file() or not os.access(p, os.X_OK):
            continue
        try:
            with open(p, 'rb') as f:
                if f.read(4) == b'\x7fELF':
                    executables.append(p)
        except OSError:
            pass
    assert executables, "No compiled C++ executable was submitted under /home/user"

    build_dir = Path(tempfile.mkdtemp(prefix='cpp_verify_'))
    compiled_bins = []
    source_groups = [sources]
    if len(sources) > 1:
        source_groups.extend([[p] for p in sources])

    for i, group in enumerate(source_groups):
        output = build_dir / f'utility_{i}'
        result = subprocess.run(
            ['g++', '-std=c++17', '-O2', *map(str, group), '-o', str(output)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            compiled_bins.append(output)

    assert compiled_bins, "Submitted C++ source could not be compiled with g++"

    config_path = Path('/home/user/chunk_config.ini')
    dump_path = Path('/home/user/project_dump.bin')
    output_dir = Path('/home/user/chunks')
    original_config = config_path.read_bytes()
    original_dump = dump_path.read_bytes()
    backup_dir = Path(tempfile.mkdtemp(prefix='chunks_backup_'))
    backup_chunks = backup_dir / 'chunks'
    if output_dir.exists():
        shutil.copytree(output_dir, backup_chunks)

    test_text = ['A🙂\n', 'ééé\n', '漢字!\n', '1234567890\n']
    test_records = [s.encode('utf-8') for s in test_text]
    max_size = 17

    dump_bytes = bytearray()
    for text in test_text:
        payload = text.encode('utf-16le')
        dump_bytes.extend(struct.pack('<I', len(payload)))
        dump_bytes.extend(payload)

    def reset_fixture():
        config_path.write_text(
            'max_chunk_size=17\noutput_dir=/home/user/chunks\n',
            encoding='utf-8',
        )
        dump_path.write_bytes(bytes(dump_bytes))
        if output_dir.exists():
            shutil.rmtree(output_dir)

    def program_passes(program):
        reset_fixture()
        try:
            result = subprocess.run(
                [str(program)],
                cwd=str(program.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            if result.returncode != 0:
                return False
            assert_outputs(str(output_dir), test_records, max_size)
            return True
        except (AssertionError, OSError, subprocess.SubprocessError):
            return False

    try:
        assert any(program_passes(p) for p in compiled_bins), (
            "The submitted C++ source does not implement the required utility on derived test data"
        )
        assert any(program_passes(p) for p in executables), (
            "No submitted compiled executable implements the required utility on derived test data"
        )
    finally:
        config_path.write_bytes(original_config)
        dump_path.write_bytes(original_dump)
        if output_dir.exists():
            shutil.rmtree(output_dir)
        if backup_chunks.exists():
            shutil.copytree(backup_chunks, output_dir)
        shutil.rmtree(backup_dir, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
