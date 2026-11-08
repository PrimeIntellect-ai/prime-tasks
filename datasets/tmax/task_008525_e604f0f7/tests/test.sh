#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

BUILD_DIR = Path('/home/user/build_dump')
ELF_DIR = Path('/home/user/elf_valid')
ELF_ARCHIVE = Path('/home/user/elf_archive.tar.gz')
CHUNK_DIR = Path('/home/user/log_chunks')
LOG_ARCHIVE = Path('/home/user/logs_archive.zip')
SUMMARY = Path('/home/user/summary.txt')
CHUNK_SIZE = 50 * 1024

EXPECTED_ELFS = sorted(['binary1_ls', 'binary2_cat', 'binary3_echo.elf'])
EXPECTED_CHUNKS = sorted([
    'system_run.log_chunk_aa', 'system_run.log_chunk_ab', 'system_run.log_chunk_ac',
    'error_dump.log_chunk_aa',
    'access.log_chunk_aa', 'access.log_chunk_ab', 'access.log_chunk_ac', 'access.log_chunk_ad'
])


def flat_regular_files(directory):
    assert directory.is_dir(), f'Required directory {directory} does not exist.'
    entries = list(directory.iterdir())
    for entry in entries:
        assert entry.is_file() and not entry.is_symlink(), f'{entry} is not a regular file.'
    return {entry.name: entry.read_bytes() for entry in entries}


def assert_valid_elf64_executable(data, label):
    with tempfile.NamedTemporaryFile() as candidate:
        candidate.write(data)
        candidate.flush()
        header = subprocess.run(
            ['readelf', '-h', candidate.name], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert header.returncode == 0, f'{label} is not parseable by readelf: {header.stderr}'
        assert re.search(r'^\s*Class:\s+ELF64\s*$', header.stdout, re.MULTILINE), \
            f'{label} is not a 64-bit ELF.'
        assert re.search(r'^\s*Type:\s+(EXEC|DYN)\b', header.stdout, re.MULTILINE), \
            f'{label} is not an ELF executable.'

        program_headers = subprocess.run(
            ['readelf', '-l', candidate.name], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert program_headers.returncode == 0, \
            f'{label} has invalid program headers: {program_headers.stderr}'
        assert re.search(r'^\s*LOAD\s', program_headers.stdout, re.MULTILINE), \
            f'{label} has no loadable program segment.'


def expected_chunk_data():
    result = {}
    for source in sorted(BUILD_DIR.iterdir(), key=lambda p: p.name):
        if source.is_file() and source.name.endswith('.log'):
            data = source.read_bytes()
            for index, offset in enumerate(range(0, len(data), CHUNK_SIZE)):
                first = chr(ord('a') + index // 26)
                second = chr(ord('a') + index % 26)
                name = f'{source.name}_chunk_{first}{second}'
                result[name] = data[offset:offset + CHUNK_SIZE]
    return result


def test_summary_txt():
    assert SUMMARY.is_file(), f'Summary file {SUMMARY} does not exist.'

    with SUMMARY.open('r') as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, f'Expected exactly 2 lines in summary.txt, found {len(content)}.'
    assert content[0] == 'VALID_ELF_COUNT=3', f'Expected VALID_ELF_COUNT=3, got {content[0]}.'
    assert content[1] == 'LOG_CHUNK_COUNT=8', f'Expected LOG_CHUNK_COUNT=8, got {content[1]}.'

    assert content == [
        f'VALID_ELF_COUNT={len(EXPECTED_ELFS)}',
        f'LOG_CHUNK_COUNT={len(expected_chunk_data())}'
    ]


def test_elf_directory_and_archive_contents():
    directory_files = flat_regular_files(ELF_DIR)
    assert sorted(directory_files) == EXPECTED_ELFS, \
        f'{ELF_DIR} contains incorrect files: {sorted(directory_files)}.'

    for name in EXPECTED_ELFS:
        source_data = (BUILD_DIR / name).read_bytes()
        assert directory_files[name] == source_data, \
            f'{ELF_DIR / name} does not match its source file.'
        assert_valid_elf64_executable(directory_files[name], str(ELF_DIR / name))

    assert ELF_ARCHIVE.is_file(), f'Archive {ELF_ARCHIVE} does not exist.'
    assert tarfile.is_tarfile(ELF_ARCHIVE), f'File {ELF_ARCHIVE} is not a valid tar archive.'

    with tarfile.open(ELF_ARCHIVE, 'r:gz') as tar:
        members = tar.getmembers()
        for member in members:
            assert member.isfile(), \
                f'Archive contains non-file element: {member.name}. Directory structure should not be included.'
            assert '/' not in member.name, \
                f'Archive contains nested paths: {member.name}. Only flat files should be included.'

        filenames = sorted(member.name for member in members)
        assert filenames == EXPECTED_ELFS, \
            f'Archive contains incorrect files. Expected {EXPECTED_ELFS}, got {filenames}.'

        for member in members:
            extracted = tar.extractfile(member)
            assert extracted is not None
            data = extracted.read()
            assert data == (BUILD_DIR / member.name).read_bytes(), \
                f'Archived {member.name} does not match its source file.'
            assert data == directory_files[member.name], \
                f'Archived {member.name} does not match {ELF_DIR / member.name}.'
            assert member.size == len(data), f'Incorrect stored size for archived {member.name}.'
            assert_valid_elf64_executable(data, f'archived {member.name}')


def test_log_directory_and_archive_contents():
    expected = expected_chunk_data()
    assert sorted(expected) == EXPECTED_CHUNKS, \
        f'Unexpected chunks derived from source logs: {sorted(expected)}.'

    directory_files = flat_regular_files(CHUNK_DIR)
    assert sorted(directory_files) == EXPECTED_CHUNKS, \
        f'{CHUNK_DIR} contains incorrect files: {sorted(directory_files)}.'

    for name, expected_data in expected.items():
        assert directory_files[name] == expected_data, \
            f'Chunk {CHUNK_DIR / name} has incorrect contents.'
        assert 0 < len(directory_files[name]) <= CHUNK_SIZE, \
            f'Chunk {name} has invalid size {len(directory_files[name])}.'
        if not name.endswith(('_chunk_ac', '_chunk_ad')):
            source_name = name.rsplit('_chunk_', 1)[0]
            source_size = (BUILD_DIR / source_name).stat().st_size
            chunk_index = ((ord(name[-2]) - ord('a')) * 26) + (ord(name[-1]) - ord('a'))
            if (chunk_index + 1) * CHUNK_SIZE <= source_size:
                assert len(directory_files[name]) == CHUNK_SIZE, \
                    f'Non-final chunk {name} is not exactly {CHUNK_SIZE} bytes.'

    assert LOG_ARCHIVE.is_file(), f'Archive {LOG_ARCHIVE} does not exist.'
    assert zipfile.is_zipfile(LOG_ARCHIVE), f'File {LOG_ARCHIVE} is not a valid zip archive.'

    with zipfile.ZipFile(LOG_ARCHIVE, 'r') as zf:
        infolist = zf.infolist()
        for info in infolist:
            assert not info.is_dir(), f'Archive contains directory: {info.filename}. Directory structure should not be included.'
            assert '/' not in info.filename, \
                f'Archive contains nested paths: {info.filename}. Only flat files should be included.'

        filenames = sorted(info.filename for info in infolist)
        assert filenames == EXPECTED_CHUNKS, \
            f'Archive contains incorrect chunk files. Expected {EXPECTED_CHUNKS}, got {filenames}.'

        assert zf.testzip() is None, 'ZIP archive contains a file with a bad CRC.'
        for info in infolist:
            data = zf.read(info)
            assert data == expected[info.filename], \
                f'Archived chunk {info.filename} has incorrect contents.'
            assert data == directory_files[info.filename], \
                f'Archived chunk {info.filename} does not match {CHUNK_DIR / info.filename}.'
            assert info.file_size == len(data), f'Incorrect stored size for archived chunk {info.filename}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
