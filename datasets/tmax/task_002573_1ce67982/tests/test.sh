#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import shutil
import string
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
BINARY_PATH = PROJECT / 'bin/log_sanitizer'
CLEAN_CORPUS_DIR = Path(tempfile.mkdtemp(prefix='logsan_clean_'))
EVIL_CORPUS_DIR = Path(tempfile.mkdtemp(prefix='logsan_evil_'))


def _write(directory, name, data):
    (directory / name).write_bytes(data)


def _random_name():
    return secrets.token_hex(12) + '.log'


def _make_corpora():
    clean_cases = [
        b'',
        b'ordinary clean log line\nsecond line\r\n',
        b'drop_table is case-sensitive',
        b'DROP-TABLE and DROP TABLE are harmless',
        b'brackets (square) and {curly} are harmless',
        bytes(c for c in range(32, 127) if c not in (ord('<'), ord('>'))),
        b'carriage\rreturn and\nnewline are permitted',
        b'prefixDROP_TABLsuffix',
        b'\x7f\x80\xff',
        b'A' * (4 * 1024 * 1024),
    ]

    alphabet = (string.ascii_letters + string.digits + ' _-.,:;!?/\\[]{}()').encode()
    for _ in range(12):
        clean_cases.append(bytes(secrets.choice(alphabet) for _ in range(500 + secrets.randbelow(1500))))

    evil_cases = [
        b'DROP_TABLE',
        b'prefix-' + b'DROP_TABLE' + b'-suffix',
        b'<',
        b'>',
        b'plain text with < one angle',
        b'plain text with one angle >',
        b'<script>alert(1)</script>',
        b'A' * (2 * 1024 * 1024) + b'DROP_TABLE' + b'B' * 1024,
    ]
    for value in range(32):
        if value not in (10, 13):
            evil_cases.append(b'valid-prefix' + bytes([value]) + b'valid-suffix')

    for data in clean_cases:
        _write(CLEAN_CORPUS_DIR, _random_name(), data)
    for data in evil_cases:
        _write(EVIL_CORPUS_DIR, _random_name(), data)


_make_corpora()


def _run(filepath):
    return subprocess.run(
        [str(BINARY_PATH), str(filepath)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f'Executable not found at {BINARY_PATH}'
    assert os.access(BINARY_PATH, os.X_OK), f'File at {BINARY_PATH} is not executable'


def test_project_sources_and_stateful_core_exist():
    makefile = PROJECT / 'Makefile'
    main_source = PROJECT / 'src/main.c'
    sanitizer_source = PROJECT / 'src/sanitizer.c'
    for path in (makefile, main_source, sanitizer_source):
        assert path.is_file(), f'Required project file is missing: {path}'

    source = sanitizer_source.read_text(errors='replace')
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert len(source.strip()) >= 150, 'src/sanitizer.c does not contain a substantive implementation'
    assert re.search(r'\b(for|while)\s*\(', source), 'sanitizer.c must process the input stream, not merely provide a stub'
    assert re.search(r'\bstruct\b|\benum\b|\bswitch\s*\(|\bstate\b|\w+\s*\[[^\]]+\]', source), \
        'sanitizer.c does not contain a custom/stateful representation for stream processing'


def test_makefile_rebuilds_and_links_mock_library():
    if BINARY_PATH.exists():
        BINARY_PATH.unlink()

    result = subprocess.run(
        ['make', '-B'], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
    )
    assert result.returncode == 0, f'make failed:\n{result.stdout}'
    assert BINARY_PATH.is_file(), 'make did not create bin/log_sanitizer'
    assert os.access(BINARY_PATH, os.X_OK), 'binary produced by make is not executable'

    dry = subprocess.run(
        ['make', '-n', '-B'], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
    )
    assert dry.returncode == 0, f'could not inspect Makefile link command:\n{dry.stdout}'

    tokens = []
    for line in dry.stdout.splitlines():
        try:
            tokens.extend(shlex.split(line))
        except ValueError:
            tokens.extend(line.split())

    expected_dir = (PROJECT / 'lib').resolve()
    direct_archive = False
    has_lmocklog = False
    library_dirs = []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token == '-lmocklog':
            has_lmocklog = True
        if token == '-L' and i + 1 < len(tokens):
            library_dirs.append(tokens[i + 1])
            i += 1
        elif token.startswith('-L') and len(token) > 2:
            library_dirs.append(token[2:])
        if token.endswith('libmocklog.a'):
            candidate = Path(token)
            if not candidate.is_absolute():
                candidate = PROJECT / candidate
            if candidate.resolve() == (expected_dir / 'libmocklog.a').resolve():
                direct_archive = True
        i += 1

    correct_search_dir = False
    for directory in library_dirs:
        candidate = Path(directory)
        if not candidate.is_absolute():
            candidate = PROJECT / candidate
        if candidate.resolve() == expected_dir:
            correct_search_dir = True

    assert direct_archive or (has_lmocklog and correct_search_dir), \
        'the link command must use project/lib/libmocklog.a or -L<project>/lib -lmocklog'


def test_clean_corpus():
    clean_files = [p for p in CLEAN_CORPUS_DIR.iterdir() if p.is_file()]
    local_dir = Path('/app/corpus/clean')
    if local_dir.is_dir():
        clean_files.extend(p for p in local_dir.iterdir() if p.is_file())
    assert len(clean_files) > 0, 'No files found in clean corpus'

    failed_files = []
    for filepath in clean_files:
        try:
            result = _run(filepath)
            if result.returncode != 0:
                failed_files.append(filepath.name)
        except subprocess.TimeoutExpired:
            failed_files.append(filepath.name + ' (timeout)')

    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(clean_files)} clean files rejected. Offending files: {", ".join(failed_files)}')


def test_evil_corpus():
    evil_files = [p for p in EVIL_CORPUS_DIR.iterdir() if p.is_file()]
    local_dir = Path('/app/corpus/evil')
    if local_dir.is_dir():
        evil_files.extend(p for p in local_dir.iterdir() if p.is_file())
    assert len(evil_files) > 0, 'No files found in evil corpus'

    failed_files = []
    for filepath in evil_files:
        try:
            result = _run(filepath)
            if result.returncode != 1:
                failed_files.append(filepath.name)
        except subprocess.TimeoutExpired:
            failed_files.append(filepath.name + ' (timeout)')

    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(evil_files)} evil files bypassed. Offending files: {", ".join(failed_files)}')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
