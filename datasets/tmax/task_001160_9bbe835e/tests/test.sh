#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

SOURCE = '/home/user/curate.c'
BINARY = '/home/user/curate'
REPORT = '/home/user/curation_report.txt'
ARTIFACTS = '/home/user/artifacts'


def expected_for_package(filename):
    data = Path(filename).read_bytes()
    assert data[:4] == b'PKG1', f'Invalid package magic in {filename}'
    assert len(data) >= 5, f'Truncated package: {filename}'

    path_len = data[4]
    path_end = 5 + path_len
    assert len(data) >= path_end + 4, f'Truncated package: {filename}'
    path_bytes = data[5:path_end]
    path = path_bytes.decode('utf-8')
    gz_size = struct.unpack_from('<I', data, path_end)[0]
    gz_data = data[path_end + 4:path_end + 4 + gz_size]
    assert len(gz_data) == gz_size, f'Truncated gzip data in {filename}'

    if '../' in path:
        return f'[REJECT] {path} (Path Traversal)'

    elf = gzip.decompress(gz_data)
    assert len(elf) >= 20 and elf[:4] == b'\x7fELF', f'Invalid ELF payload in {filename}'
    machine = struct.unpack_from('<H', elf, 0x12)[0]
    return f'[ACCEPT] {path} (Arch: 0x{machine:x})'


def run_curate(filename, expected):
    result = subprocess.run(
        [BINARY, filename],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f'curate failed for {filename} with status {result.returncode}: {result.stderr}'
    )
    assert result.stdout == expected + '\n', (
        f'Unexpected output for {filename}. Expected {expected!r}, got {result.stdout!r}'
    )


def make_elf(machine):
    elf = bytearray(b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00')
    elf += struct.pack('<HHI', 2, machine, 1)
    elf += b'\x00' * (64 - len(elf))
    return bytes(elf)


def make_package(filename, embedded_path, machine):
    path_bytes = embedded_path.encode('utf-8')
    compressed = gzip.compress(make_elf(machine))
    Path(filename).write_bytes(
        b'PKG1'
        + struct.pack('<B', len(path_bytes))
        + path_bytes
        + struct.pack('<I', len(compressed))
        + compressed
    )


def test_curate_c_exists():
    assert os.path.isfile('/home/user/curate.c'), "/home/user/curate.c is missing. You must write the C program."


def test_curation_report_exists():
    assert os.path.isfile('/home/user/curation_report.txt'), "/home/user/curation_report.txt is missing. You must generate the report."


def test_curation_report_contents():
    expected_lines = [
        "[ACCEPT] bin/server (Arch: 0x3e)",
        "[ACCEPT] lib/module.so (Arch: 0x28)",
        "[REJECT] ../../../etc/passwd (Path Traversal)",
        "[REJECT] usr/bin/../lib/test (Path Traversal)"
    ]

    with open('/home/user/curation_report.txt', 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the report, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'."


def test_source_compiles_cleanly():
    result = subprocess.run(
        ['gcc', SOURCE, '-o', BINARY, '-lz'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'gcc failed:\n{result.stdout}{result.stderr}'
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)


def test_program_on_eligible_repository_packages_and_report():
    eligible = []
    for root, _, files in os.walk(ARTIFACTS):
        for name in files:
            filename = os.path.join(root, name)
            if name.endswith('.pkg') and os.path.getsize(filename) < 100 * 1024:
                eligible.append(filename)

    expected_lines = []
    for filename in eligible:
        expected = expected_for_package(filename)
        expected_lines.append(expected)
        run_curate(filename, expected)

    expected_lines.sort()
    with open(REPORT, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        'The report does not match the sorted outputs for all and only eligible .pkg files.'
    )


def test_program_parses_new_gzip_elf_packages_and_traversal():
    token = secrets.token_hex(8)
    machines = [0x0a, 0xbeef, secrets.randbelow(0xffff) + 1]

    with tempfile.TemporaryDirectory(prefix='curate-verifier-') as directory:
        for index, machine in enumerate(machines):
            embedded_path = f'opt/{token}/module{index}.bin'
            filename = os.path.join(directory, f'random-{index}.pkg')
            make_package(filename, embedded_path, machine)
            run_curate(filename, f'[ACCEPT] {embedded_path} (Arch: 0x{machine:x})')

        malicious_path = f'safe/{token}/../../escape'
        malicious_file = os.path.join(directory, 'traversal.pkg')
        path_bytes = malicious_path.encode('utf-8')
        # Deliberately invalid gzip bytes: traversal must be rejected immediately,
        # without attempting to decompress or inspect the payload.
        Path(malicious_file).write_bytes(
            b'PKG1'
            + struct.pack('<B', len(path_bytes))
            + path_bytes
            + struct.pack('<I', 4)
            + b'nope'
        )
        run_curate(malicious_file, f'[REJECT] {malicious_path} (Path Traversal)')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
