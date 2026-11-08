#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
FULL = Path('/home/user/backup_full.tar.gz')
INC = Path('/home/user/backup_inc.tar.gz')
SNAR = Path('/home/user/backup.snar')

INDEX_BYTES = b'data_01.txt,core_module.cpp\ndata_02.txt,utils_strings.cpp\n'
OLD_CORE = b'/* Initialisation de la m\xe9moire */\nint main() { return 0; }\n'
OLD_UTILS = b'/* A\xf1adir funcionalidad */\nvoid add() {}\n'
NEW_CORE = b'/* Initialisation de la m\xc3\xa9moire */\nint main() { return 0; }\n'
NEW_UTILS = b'/* A\xc3\xb1adir funcionalidad */\nvoid add() {}\n'


def test_project_directory_exists():
    assert PROJECT.is_dir(), 'The /home/user/project/ directory does not exist.'


def test_backup_full_exists_and_valid():
    assert FULL.is_file(), f'{FULL} does not exist.'
    assert tarfile.is_tarfile(FULL), f'{FULL} is not a valid tar archive.'


def test_backup_snar_exists():
    assert SNAR.is_file(), f'{SNAR} does not exist.'
    assert SNAR.stat().st_size > 0, f'{SNAR} is empty.'


def test_process_cpp_and_executable_exist():
    source = Path('/home/user/process.cpp')
    executable = Path('/home/user/process')
    assert source.is_file(), '/home/user/process.cpp does not exist.'
    assert executable.is_file(), '/home/user/process executable does not exist.'
    assert os.access(executable, os.X_OK), '/home/user/process is not executable.'
    assert executable.read_bytes()[:4] == b'\x7fELF', '/home/user/process is not a compiled native executable.'


def test_converted_files_content():
    core_module = PROJECT / 'core_module.cpp'
    utils_strings = PROJECT / 'utils_strings.cpp'
    assert core_module.is_file(), f'{core_module} does not exist.'
    assert utils_strings.is_file(), f'{utils_strings} does not exist.'
    assert core_module.read_bytes().strip() == NEW_CORE.strip(), f'Content of {core_module} is incorrect or not valid UTF-8.'
    assert utils_strings.read_bytes().strip() == NEW_UTILS.strip(), f'Content of {utils_strings} is incorrect or not valid UTF-8.'


def test_old_files_deleted():
    assert not (PROJECT / 'data_01.txt').exists(), 'data_01.txt was not deleted.'
    assert not (PROJECT / 'data_02.txt').exists(), 'data_02.txt was not deleted.'


def test_backup_inc_exists_and_valid():
    assert INC.is_file(), f'{INC} does not exist.'
    assert tarfile.is_tarfile(INC), f'{INC} is not a valid tar archive.'


def test_completion_log():
    log_path = Path('/home/user/completion.log')
    assert log_path.is_file(), f'{log_path} does not exist.'
    with log_path.open('r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = ['core_module.cpp', 'index.csv', 'utils_strings.cpp']
    assert lines == expected_lines, f'Contents of {log_path} do not match the expected sorted list of files.'


def _safe_archive_members(path):
    with tarfile.open(path, 'r:gz') as tf:
        members = tf.getmembers()
        assert members, f'{path} is empty.'
        for member in members:
            p = Path(member.name)
            assert not p.is_absolute() and '..' not in p.parts, f'Unsafe path in {path}: {member.name}'
            assert member.isfile() or member.isdir(), f'Unexpected non-file entry in {path}: {member.name}'
        assert any(member.type == tarfile.GNUTYPE_DUMPDIR for member in members), (
            f'{path} does not contain GNU listed-incremental directory metadata.'
        )
        regular = {Path(m.name).name: tf.extractfile(m).read() for m in members if m.isfile()}
    return regular


def _files_by_basename(root):
    return {p.name: p.read_bytes() for p in Path(root).rglob('*') if p.is_file()}


def test_listed_incremental_archives_and_contents():
    full_regular = _safe_archive_members(FULL)
    assert full_regular == {
        'index.csv': INDEX_BYTES,
        'data_01.txt': OLD_CORE,
        'data_02.txt': OLD_UTILS,
    }, 'The full backup is not the unprocessed baseline project.'

    inc_regular = _safe_archive_members(INC)
    assert inc_regular == {
        'core_module.cpp': NEW_CORE,
        'utils_strings.cpp': NEW_UTILS,
    }, 'The incremental backup does not contain exactly the new/modified source files.'

    with tempfile.TemporaryDirectory() as td:
        restore = Path(td) / 'restore'
        restore.mkdir()
        subprocess.run(
            ['tar', '--listed-incremental=/dev/null', '-xzf', str(FULL), '-C', str(restore)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert _files_by_basename(restore) == {
            'index.csv': INDEX_BYTES,
            'data_01.txt': OLD_CORE,
            'data_02.txt': OLD_UTILS,
        }, 'Restoring the full listed-incremental archive does not reproduce the baseline.'

        subprocess.run(
            ['tar', '--listed-incremental=/dev/null', '-xzf', str(INC), '-C', str(restore)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert _files_by_basename(restore) == {
            'index.csv': INDEX_BYTES,
            'core_module.cpp': NEW_CORE,
            'utils_strings.cpp': NEW_UTILS,
        }, 'Applying the incremental archive does not reproduce the final project or its deletions.'

    with tempfile.TemporaryDirectory() as td:
        snapshot_copy = Path(td) / 'backup.snar'
        probe_archive = Path(td) / 'probe.tar'
        shutil.copyfile(SNAR, snapshot_copy)
        result = subprocess.run(
            ['tar', f'--listed-incremental={snapshot_copy}', '-cf', str(probe_archive),
             '-C', '/home/user', 'project'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, f'backup.snar is not valid GNU tar snapshot metadata: {result.stderr.decode(errors="replace")}'


def _exercise_processor(executable):
    token = uuid.uuid4().hex
    old1 = f'legacy_{token}_a.txt'
    old2 = f'legacy_{token}_b.txt'
    new1 = f'renamed_{token}_a.cpp'
    new2 = f'renamed_{token}_b.cpp'
    raw1 = b'Cafe: \xe9; pound: \xa3; upper: \xc4\nSecond line\n'
    raw2 = b'Espanol: \xf1; extremes: \x80 \xff\n'

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        (work / 'index.csv').write_bytes(f'{old1},{new1}\n{old2},{new2}\n'.encode('ascii'))
        (work / old1).write_bytes(raw1)
        (work / old2).write_bytes(raw2)
        untouched = work / 'untouched.bin'
        untouched.write_bytes(b'leave me alone')

        result = subprocess.run([str(executable)], cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f'{executable} failed on a valid index.csv: {result.stderr.decode(errors="replace")}'
        assert not (work / old1).exists() and not (work / old2).exists(), 'Processor did not delete dynamically listed old files.'
        assert (work / new1).read_bytes() == raw1.decode('latin-1').encode('utf-8'), 'Processor converted the first ISO-8859-1 input incorrectly.'
        assert (work / new2).read_bytes() == raw2.decode('latin-1').encode('utf-8'), 'Processor converted the second ISO-8859-1 input incorrectly.'
        assert untouched.read_bytes() == b'leave me alone', 'Processor modified an unlisted file.'
        assert (work / 'index.csv').is_file(), 'Processor deleted index.csv.'


def test_submitted_executable_parses_csv_and_converts_latin1():
    _exercise_processor(Path('/home/user/process'))


def test_process_cpp_builds_and_implements_processor():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = Path(td) / 'process-rebuilt'
        result = subprocess.run(
            ['g++', '-std=c++17', '/home/user/process.cpp', '-o', str(rebuilt)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
        assert result.returncode == 0, f'process.cpp does not compile as C++17: {result.stderr.decode(errors="replace")}'
        _exercise_processor(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
