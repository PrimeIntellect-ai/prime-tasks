#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tarfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/workspace/archive_tool')
PACK_PATH = Path('/home/user/data/legacy_project.pack')
LOG_PATH = Path('/home/user/workspace/extraction.log')
TAR_PATH = Path('/home/user/workspace/safe_project.tar.gz')


def run_project():
    assert PROJECT.is_dir(), f"Rust project missing at {PROJECT}"
    assert (PROJECT / 'Cargo.toml').is_file(), "Cargo.toml is missing"
    assert list(PROJECT.rglob('*.rs')), "Rust project contains no Rust source files"

    LOG_PATH.unlink(missing_ok=True)
    TAR_PATH.unlink(missing_ok=True)

    env = os.environ.copy()
    env['CARGO_NET_OFFLINE'] = 'true'
    try:
        result = subprocess.run(
            ['cargo', 'run', '--quiet'],
            cwd=PROJECT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Rust program timed out')

    assert result.returncode == 0, (
        f"Rust program failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_extraction_log():
    log_path = '/home/user/workspace/extraction.log'
    assert os.path.isfile(log_path), f"Log file missing at {log_path}"

    with open(log_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Original: src/Main-File.txt -> Sanitized: main_file.txt",
        "Original: ../outside-file.txt -> Sanitized: outside_file.txt",
        "Original: deep/dir/../../../secret-Data.txt -> Sanitized: secret_data.txt"
    ]

    assert lines == expected_lines, f"Extraction log content is incorrect. Got: {lines}"


def test_safe_project_tar_gz():
    tar_path = '/home/user/workspace/safe_project.tar.gz'
    assert os.path.isfile(tar_path), f"Tarball missing at {tar_path}"

    expected_files = {
        "main_file.txt": "Café".encode('utf-8'),
        "outside_file.txt": "Hello World".encode('utf-8'),
        "secret_data.txt": "Secret information here.".encode('utf-8')
    }

    try:
        with tarfile.open(tar_path, 'r:gz') as tar:
            members = tar.getmembers()
            extracted_names = [m.name for m in members]

            for expected_name in expected_files.keys():
                assert expected_name in extracted_names, f"Missing {expected_name} in tarball"

            for m in members:
                assert m.isfile(), f"Tarball contains a non-file entry (directories are not allowed): {m.name}"
                assert m.name in expected_files, f"Unexpected file in tarball: {m.name}"

                f = tar.extractfile(m)
                assert f is not None, f"Could not extract file {m.name}"
                content = f.read()

                assert content == expected_files[m.name], f"Content mismatch for {m.name}. Expected {expected_files[m.name]}, got {content}"
    except tarfile.ReadError:
        pytest.fail(f"Could not read {tar_path} as a gzip-compressed tarball")


def write_pack(entries):
    with PACK_PATH.open('wb') as f:
        f.write(b'PACK')
        f.write(struct.pack('<I', len(entries)))
        for path, flag, raw_content in entries:
            path_bytes = path.encode('utf-8')
            f.write(struct.pack('<H', len(path_bytes)))
            f.write(path_bytes)
            f.write(struct.pack('B', flag))
            f.write(struct.pack('<I', len(raw_content)))
            f.write(raw_content)


def assert_dynamic_outputs(entries):
    expected_log = []
    expected_files = {}
    for path, _flag, _raw, decoded in entries:
        sanitized = path.rsplit('/', 1)[-1].lower().replace('-', '_')
        expected_log.append(f"Original: {path} -> Sanitized: {sanitized}")
        expected_files[sanitized] = decoded.encode('utf-8')

    assert LOG_PATH.is_file(), f"Log file missing at {LOG_PATH}"
    with LOG_PATH.open('r', encoding='utf-8') as f:
        actual_log = [line.rstrip('\r\n') for line in f]
    assert actual_log == expected_log, f"Dynamic extraction log is incorrect. Got: {actual_log}"

    assert TAR_PATH.is_file(), f"Tarball missing at {TAR_PATH}"
    try:
        with tarfile.open(TAR_PATH, 'r:gz') as tar:
            members = tar.getmembers()
            names = [member.name for member in members]
            assert names == list(expected_files), f"Tarball entries are incorrect. Got: {names}"
            assert len(names) == len(set(names)), "Tarball contains duplicate entries"
            for member in members:
                assert member.isfile(), f"Tarball contains a non-file entry: {member.name}"
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not extract {member.name}"
                assert extracted.read() == expected_files[member.name], f"Content mismatch for {member.name}"
    except tarfile.ReadError:
        pytest.fail(f"Could not read {TAR_PATH} as a gzip-compressed tarball")


def test_program_executes_and_handles_unseen_archive():
    original_pack = PACK_PATH.read_bytes()

    # Execute the submitted Rust project on the archive supplied by the task,
    # then retain all assertions from the original verifier.
    run_project()
    test_extraction_log()
    test_safe_project_tar_gz()

    token = secrets.token_hex(8)
    decoded_entries = [
        (
            f"../../private/Report-{token.upper()}-File.TXT",
            1,
            f"Café € – dynamic {token}",
        ),
        (
            f"deep/one/two/../../../Résumé-{token}-Data.txt",
            2,
            f"UTF16 snowman ☃ {token}",
        ),
        (
            f"source/tree/Plain-{token}-Text.md",
            0,
            f"UTF-8 日本語 {token}",
        ),
    ]
    entries = []
    for path, flag, decoded in decoded_entries:
        if flag == 0:
            raw = decoded.encode('utf-8')
        elif flag == 1:
            raw = decoded.encode('windows-1252')
        else:
            raw = decoded.encode('utf-16le')
        entries.append((path, flag, raw, decoded))

    try:
        write_pack([(path, flag, raw) for path, flag, raw, _decoded in entries])
        run_project()
        assert_dynamic_outputs(entries)
    finally:
        PACK_PATH.write_bytes(original_pack)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
