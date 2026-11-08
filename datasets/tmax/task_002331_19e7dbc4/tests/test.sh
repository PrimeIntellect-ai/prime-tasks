#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import subprocess
import zlib
from pathlib import Path

import pytest

PROJECT = Path('/home/user/tmr_tool')
DATA_LAKE = Path('/home/user/data_lake')
BUILD = Path('/tmp/tmr_verify_build')


def tmr_encode(data: bytes) -> bytes:
    return bytes(b for b in data for _ in range(3))


def find_built_executable(name: str) -> Path:
    candidates = [p for p in BUILD.rglob(name) if p.is_file() and os.access(p, os.X_OK)]
    assert candidates, f'Built executable {name} was not found under {BUILD}.'
    for candidate in candidates:
        if candidate.read_bytes()[:4] == b'\x7fELF':
            return candidate
    pytest.fail(f'{name} is not an ELF executable.')


@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    cmake_file = PROJECT / 'CMakeLists.txt'
    assert PROJECT.is_dir(), f'{PROJECT} is missing.'
    assert cmake_file.is_file(), f'{cmake_file} is missing.'

    cmake_text = cmake_file.read_text(encoding='utf-8', errors='ignore')
    lower = cmake_text.lower()
    assert 'fetchcontent' in lower, 'CMakeLists.txt does not use FetchContent.'
    assert 'rapidcheck' in lower, 'CMakeLists.txt does not integrate RapidCheck.'
    assert 'github.com/emil-e/rapidcheck' in lower, 'CMakeLists.txt does not fetch the required RapidCheck repository.'
    assert 'zlib' in lower, 'CMakeLists.txt does not find or link zlib.'
    assert 'tmr_test' in cmake_text, 'CMake target tmr_test is missing.'
    assert 'tmr_process' in cmake_text, 'CMake target tmr_process is missing.'

    shutil.rmtree(BUILD, ignore_errors=True)
    subprocess.run(
        ['cmake', '-S', str(PROJECT), '-B', str(BUILD), '-DCMAKE_BUILD_TYPE=Release'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    subprocess.run(
        ['cmake', '--build', str(BUILD), '--target', 'tmr_test', 'tmr_process', '-j2'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )

    test_exe = find_built_executable('tmr_test')
    process_exe = find_built_executable('tmr_process')

    test_env = os.environ.copy()
    test_env['RC_PARAMS'] = 'max_success=200'
    test_run = subprocess.run(
        [str(test_exe)],
        cwd=str(BUILD),
        env=test_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    Path('/home/user/test_results.log').write_text(test_run.stdout, encoding='utf-8')
    assert test_run.returncode == 0, f'tmr_test failed:\n{test_run.stdout}'

    nonce = secrets.token_hex(8)
    dynamic_dir = DATA_LAKE / ('verifier_' + nonce) / 'deep'
    dynamic_dir.mkdir(parents=True)
    (dynamic_dir / 'random_payload.dat').write_bytes(secrets.token_bytes(4097))
    (dynamic_dir / 'empty.dat').write_bytes(b'')
    (dynamic_dir / 'ignored.txt').write_bytes(secrets.token_bytes(37))

    for old_backup in DATA_LAKE.rglob('*.dat.tmr'):
        old_backup.unlink()
    report = Path('/home/user/report.csv')
    if report.exists():
        report.unlink()

    process_run = subprocess.run(
        [str(process_exe), str(DATA_LAKE)],
        cwd=str(BUILD),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert process_run.returncode == 0, f'tmr_process failed:\n{process_run.stdout}'


def test_test_results_log():
    log_path = '/home/user/test_results.log'
    assert os.path.isfile(log_path), f'{log_path} is missing.'
    with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    assert 'OK, passed' in content or 'success' in content.lower(), f'RapidCheck success message not found in {log_path}.'


def test_report_csv():
    csv_path = '/home/user/report.csv'
    assert os.path.isfile(csv_path), f'{csv_path} is missing.'

    expected_rows = {
        'financials/2004.dat': '9c19b0bc',
        'engineering/blueprint.dat': '17f92023',
        'misc.dat': '36a8d3e2'
    }

    actual_rows = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 2:
                actual_rows[row[0].strip()] = row[1].strip().lower()

    for path, expected_crc in expected_rows.items():
        assert path in actual_rows, f'Missing entry for {path} in {csv_path}.'
        assert actual_rows[path] == expected_crc, f'Incorrect CRC32 for {path}. Expected {expected_crc}, got {actual_rows[path]}.'


def test_tmr_files():
    files_to_check = {
        '/home/user/data_lake/financials/2004.dat': b'CONFIDENTIAL_DATA_A',
        '/home/user/data_lake/engineering/blueprint.dat': b'PROJECT_BLUEPRINT_V1',
        '/home/user/data_lake/misc.dat': b'MISC_DATA_99'
    }

    for original_path, original_content in files_to_check.items():
        tmr_path = original_path + '.tmr'
        assert os.path.isfile(tmr_path), f'TMR encoded file {tmr_path} is missing.'
        expected_tmr_content = tmr_encode(original_content)
        with open(tmr_path, 'rb') as f:
            actual_tmr_content = f.read()
        assert actual_tmr_content == expected_tmr_content, f'Content of {tmr_path} does not match expected TMR encoding.'


def test_processing_of_all_dynamic_inputs():
    dat_files = sorted(DATA_LAKE.rglob('*.dat'))
    assert len(dat_files) >= 5

    expected = {}
    for source in dat_files:
        data = source.read_bytes()
        relative = source.relative_to(DATA_LAKE).as_posix()
        expected[relative] = f'{zlib.crc32(data) & 0xffffffff:08x}'
        backup = Path(str(source) + '.tmr')
        assert backup.is_file(), f'Missing dynamically generated backup {backup}.'
        assert backup.read_bytes() == tmr_encode(data), f'Incorrect TMR encoding for {relative}.'

    actual = {}
    with open('/home/user/report.csv', newline='', encoding='utf-8') as f:
        for row in csv.reader(f):
            if len(row) >= 2:
                path, checksum = row[0].strip(), row[1].strip()
                actual[path] = checksum

    for path, checksum in expected.items():
        assert path in actual, f'Missing report entry for dynamically discovered file {path}.'
        assert re.fullmatch(r'[0-9a-f]{8}', actual[path]), f'Checksum for {path} is not lowercase 8-character hex.'
        assert actual[path] == checksum, f'Incorrect dynamically derived CRC32 for {path}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
