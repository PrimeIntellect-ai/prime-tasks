#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import os
import secrets
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/process_logs.py')
MASTER = Path('/home/user/old_logs/master_archive.tar')
INTERMEDIATE = Path('/home/user/critical_errors.txt')
SORTED = Path('/home/user/critical_errors_sorted.txt')

EXPECTED_SORTED = [
    'CRITICAL_FAILURE: Database connection lost in app A',
    'CRITICAL_FAILURE: Disk full on node A1',
    'CRITICAL_FAILURE: Memory leak detected in B module',
    'CRITICAL_FAILURE: Process crashed in app B unexpectedly',
]

EXPECTED_ORIGINAL_ORDER = [
    'CRITICAL_FAILURE: Disk full on node A1',
    'CRITICAL_FAILURE: Database connection lost in app A',
    'CRITICAL_FAILURE: Memory leak detected in B module',
    'CRITICAL_FAILURE: Process crashed in app B unexpectedly',
]


def test_critical_errors_sorted_exists():
    assert os.path.isfile(SORTED), 'The file /home/user/critical_errors_sorted.txt does not exist.'


def test_critical_errors_sorted_content():
    with open(SORTED, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]
    assert actual_lines == EXPECTED_SORTED, f'Expected lines {EXPECTED_SORTED}, but got {actual_lines}'


def test_no_intermediate_files_extracted():
    old_logs_dir = '/home/user/old_logs'
    files_in_dir = os.listdir(old_logs_dir)
    assert 'master_archive.tar' in files_in_dir, 'master_archive.tar is missing from /home/user/old_logs'
    unexpected_files = [f for f in files_in_dir if f != 'master_archive.tar']
    assert not unexpected_files, f'Found unexpected extracted files in {old_logs_dir}: {unexpected_files}'


def test_python_script_exists():
    assert os.path.isfile(SCRIPT), 'The python script /home/user/process_logs.py does not exist.'


def test_script_is_real_python_using_tarfile_without_extracting():
    mode = os.stat(SCRIPT, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), 'process_logs.py must be a regular file.'
    source = SCRIPT.read_text()
    assert source.strip(), 'process_logs.py is empty.'
    tree = ast.parse(source, filename=str(SCRIPT))
    imports_tarfile = any(
        (isinstance(node, ast.Import) and any(alias.name == 'tarfile' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'tarfile')
        for node in ast.walk(tree)
    )
    assert imports_tarfile, 'process_logs.py must import and use the tarfile module.'
    forbidden = [
        node.attr for node in ast.walk(tree)
        if isinstance(node, ast.Attribute) and node.attr in {'extract', 'extractall'}
    ]
    assert not forbidden, 'The script must inspect archive members in memory, not extract them to disk.'


def test_redirected_output_matches_script_on_original_archive():
    assert INTERMEDIATE.is_file(), '/home/user/critical_errors.txt does not exist.'
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f'process_logs.py failed: {result.stderr}'
    produced = result.stdout.splitlines()
    redirected = INTERMEDIATE.read_text().splitlines()
    assert produced == EXPECTED_ORIGINAL_ORDER, f'Unexpected script output: {produced}'
    assert redirected == produced, 'critical_errors.txt does not match the script standard output.'


def _tar_bytes(members):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w') as archive:
        for name, data in members:
            encoded = data if isinstance(data, bytes) else data.encode('utf-8')
            info = tarfile.TarInfo(name)
            info.size = len(encoded)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(encoded))
    return output.getvalue()


def test_script_processes_unseen_nested_archive_in_memory():
    token = secrets.token_hex(10)
    expected = [
        f'CRITICAL_FAILURE: alpha-{token}',
        f'CRITICAL_FAILURE: zeta-{token}',
        f'CRITICAL_FAILURE: beta-{token}',
    ]

    inner_one = _tar_bytes([
        ('logs/first.log', f'INFO: start\n  {expected[0]}  \n{expected[1]}\nINFO: end\n'),
        ('logs/ignored.txt', f'{expected[2]}\n'),
    ])
    inner_two = _tar_bytes([
        ('second.log', f'DEBUG: value\n\t{expected[2]}\t\n'),
        ('empty.log', 'INFO: no failure here\n'),
    ])
    generated_master = _tar_bytes([
        (f'bundle-{token}-one.tar', inner_one),
        (f'bundle-{token}-two.tar', inner_two),
        ('metadata.txt', 'not an inner archive\n'),
    ])

    original_master = MASTER.read_bytes()
    try:
        MASTER.write_bytes(generated_master)
        with tempfile.TemporaryDirectory(prefix='verify-process-logs-') as workdir:
            stdout_path = Path(workdir) / 'stdout.txt'
            stderr_path = Path(workdir) / 'stderr.txt'
            with stdout_path.open('wb') as stdout_file, stderr_path.open('wb') as stderr_file:
                result = subprocess.run(
                    ['python3', str(SCRIPT)],
                    cwd=workdir,
                    stdout=stdout_file,
                    stderr=stderr_file,
                    timeout=15,
                )
            stderr = stderr_path.read_text(errors='replace')
            assert result.returncode == 0, f'process_logs.py failed on an unseen archive: {stderr}'
            actual = stdout_path.read_text().splitlines()
            assert actual == expected, f'Expected dynamically derived lines {expected}, but got {actual}'
            assert set(os.listdir(workdir)) == {'stdout.txt', 'stderr.txt'}, 'The script extracted archive members to disk.'

        files_in_old_logs = os.listdir(MASTER.parent)
        assert files_in_old_logs == ['master_archive.tar'], f'Archive members were written to disk: {files_in_old_logs}'
    finally:
        MASTER.write_bytes(original_master)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
