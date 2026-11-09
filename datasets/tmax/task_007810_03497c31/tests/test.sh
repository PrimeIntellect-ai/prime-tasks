#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_curator.py
import os
import shutil
import subprocess
from pathlib import Path

import pytest

SAFE_DIR = Path('/home/user/safe_artifacts')
QUARANTINE_DIR = Path('/home/user/quarantine')
LOG_PATH = Path('/home/user/quarantine.log')
SOURCE_PATH = Path('/home/user/curator.cpp')
BINARY_PATH = Path('/home/user/curator')
ORIGINAL_ARCHIVE = Path('/home/user/incoming/artifacts.tar')


def clean_outputs():
    shutil.rmtree(SAFE_DIR, ignore_errors=True)
    shutil.rmtree(QUARANTINE_DIR, ignore_errors=True)
    SAFE_DIR.mkdir(parents=True)
    QUARANTINE_DIR.mkdir(parents=True)
    if LOG_PATH.exists() or LOG_PATH.is_symlink():
        LOG_PATH.unlink()


def run_curator(binary, archive):
    subprocess.run(
        [str(binary), str(archive)],
        cwd='/home/user',
        check=True,
        timeout=15,
    )


def test_safe_artifacts_extracted():
    safe1_path = '/home/user/safe_artifacts/safe1.bin'
    safe2_path = '/home/user/safe_artifacts/safe2.bin'

    assert os.path.exists(safe1_path), f'Safe artifact {safe1_path} was not extracted.'
    with open(safe1_path, 'rb') as f:
        assert f.read() == b'safe data 1\n', f'Content of {safe1_path} is incorrect.'

    assert os.path.exists(safe2_path), f'Safe artifact {safe2_path} was not extracted.'
    with open(safe2_path, 'rb') as f:
        assert f.read() == b'safe data 2\n', f'Content of {safe2_path} is incorrect.'


def test_malicious_artifacts_quarantined():
    mal1_path = '/home/user/quarantine/1.bin'
    mal2_path = '/home/user/quarantine/3.bin'

    assert os.path.exists(mal1_path), f'Malicious artifact was not quarantined at {mal1_path}.'
    with open(mal1_path, 'rb') as f:
        assert f.read() == b'malicious data A\n', f'Content of {mal1_path} is incorrect.'

    assert os.path.exists(mal2_path), f'Malicious artifact was not quarantined at {mal2_path}.'
    with open(mal2_path, 'rb') as f:
        assert f.read() == b'malicious data B\n', f'Content of {mal2_path} is incorrect.'


def test_quarantine_log():
    log_path = '/home/user/quarantine.log'
    assert os.path.exists(log_path), f'Quarantine log {log_path} is missing.'

    with open(log_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ['../escape.bin', '/etc/fake_shadow']
    assert lines == expected_lines, f'Quarantine log does not contain the expected entries. Found: {lines}'


def test_cpp_program_exists():
    cpp_path = '/home/user/curator.cpp'
    bin_path = '/home/user/curator'

    assert os.path.exists(cpp_path), f'C++ source file {cpp_path} does not exist.'
    assert os.path.exists(bin_path), f'Compiled binary {bin_path} does not exist.'
    assert os.access(bin_path, os.X_OK), f'Compiled binary {bin_path} is not executable.'
    with open(bin_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'Compiled binary {bin_path} is not an ELF executable.'


def make_header(name, size):
    encoded = name.encode('utf-8')
    assert len(encoded) < 100
    header = bytearray(512)
    header[0:len(encoded)] = encoded
    header[100:108] = b'0000644\0'
    header[108:116] = b'0000000\0'
    header[116:124] = b'0000000\0'
    header[124:136] = f'{size:011o}\0'.encode('ascii')
    header[136:148] = b'00000000000\0'
    header[148:156] = b'        '
    header[156:157] = b'0'
    header[257:263] = b'ustar\0'
    header[263:265] = b'00'
    checksum = sum(header)
    header[148:156] = f'{checksum:06o}\0 '.encode('ascii')
    return bytes(header)


def write_archive(path, entries):
    with open(path, 'wb') as f:
        for name, data in entries:
            f.write(make_header(name, len(data)))
            f.write(data)
            f.write(b'\0' * ((-len(data)) % 512))
        f.write(b'\0' * 1024)


def check_generated_results(entries, malicious_indices):
    expected_safe = {name: data for i, (name, data) in enumerate(entries) if i not in malicious_indices}
    expected_bad = {f'{i}.bin': entries[i][1] for i in malicious_indices}

    assert {p.name for p in SAFE_DIR.iterdir()} == set(expected_safe)
    for name, data in expected_safe.items():
        assert (SAFE_DIR / name).is_file()
        assert (SAFE_DIR / name).read_bytes() == data

    assert {p.name for p in QUARANTINE_DIR.iterdir()} == set(expected_bad)
    for name, data in expected_bad.items():
        assert (QUARANTINE_DIR / name).is_file()
        assert (QUARANTINE_DIR / name).read_bytes() == data

    expected_log = [entries[i][0] for i in malicious_indices]
    assert LOG_PATH.is_file()
    assert LOG_PATH.read_text(encoding='utf-8').splitlines() == expected_log


def test_curator_end_to_end(tmp_path):
    test_cpp_program_exists()

    # Preserve the original final-state assertions, but first require the submitted
    # executable to produce that state from the supplied archive.
    clean_outputs()
    run_curator(BINARY_PATH, ORIGINAL_ARCHIVE)
    test_safe_artifacts_extracted()
    test_malicious_artifacts_quarantined()
    test_quarantine_log()

    token = os.urandom(10).hex()
    absolute_name = f'/tmp/curator_abs_{token}.bin'
    dotted_dir_name = f'x{token}../trap.bin'
    parent_name = f'../curator_parent_{token}.bin'
    entries = [
        (f'safe_{token}_a.bin', os.urandom(733)),
        (absolute_name, os.urandom(19)),
        (f'safe_{token}_empty.bin', b''),
        (dotted_dir_name, b'embedded-dot-dot-slash\x00payload'),
        (f'safe_{token}_block.bin', os.urandom(512)),
        (parent_name, os.urandom(1029)),
    ]
    malicious_indices = [1, 3, 5]
    archive = tmp_path / 'generated.tar'
    write_archive(archive, entries)

    forbidden = [
        Path(absolute_name),
        Path('/home/user') / dotted_dir_name,
        Path('/home/user') / parent_name,
    ]
    for path in forbidden:
        if path.is_file() or path.is_symlink():
            path.unlink()

    clean_outputs()
    run_curator(BINARY_PATH, archive)
    check_generated_results(entries, malicious_indices)
    assert all(not path.exists() for path in forbidden)

    # Ensure the submitted C++ source itself builds into a working implementation.
    rebuilt = tmp_path / 'curator-rebuilt'
    subprocess.run(
        ['g++', '-O2', '-o', str(rebuilt), str(SOURCE_PATH)],
        check=True,
        timeout=30,
    )
    clean_outputs()
    run_curator(rebuilt, archive)
    check_generated_results(entries, malicious_indices)
    assert all(not path.exists() for path in forbidden)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_curator.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
