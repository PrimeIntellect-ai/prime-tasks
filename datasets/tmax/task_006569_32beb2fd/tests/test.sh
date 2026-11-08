#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import fcntl
import json
import os
import random
import string
import subprocess
import tempfile
import time

SCRIPT_PATH = '/home/user/tracker.py'
INI_PATH = '/home/user/tracker.ini'


def rle(value):
    if not value:
        return ''
    result = []
    current = value[0]
    count = 1
    for char in value[1:]:
        if char == current:
            count += 1
        else:
            result.append(f'{count}{current}')
            current = char
            count = 1
    result.append(f'{count}{current}')
    return ''.join(result)


def write_ini(archive_path):
    with open(INI_PATH, 'w', encoding='utf-8') as handle:
        handle.write('[Settings]\n')
        handle.write(f'archive_path = {archive_path}\n')


def test_tracker_script_exists():
    script_path = '/home/user/tracker.py'
    assert os.path.isfile(script_path), f'The script {script_path} does not exist.'


def test_archive_file_contains_expected_output():
    archive_file = '/home/user/archive.dat'
    assert os.path.isfile(archive_file), f'The archive file {archive_file} does not exist. Did the script run successfully?'

    with open(archive_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        'service1.json:5A3B2C5D',
        'database.csv:3X2Y4Z',
        'cache.json:413223'
    }

    actual_lines = set(lines)
    missing = expected_lines - actual_lines
    assert not missing, f'The archive file is missing the following expected lines: {missing}'
    assert expected_lines.issubset(actual_lines), f'Expected {expected_lines} to be in {actual_lines}'


def test_tracker_behavior_ini_parsing_formats_and_rle():
    with open(INI_PATH, 'rb') as handle:
        original_ini = handle.read()

    try:
        with tempfile.TemporaryDirectory(prefix='tracker-test-') as directory:
            archive = os.path.join(directory, 'dynamic-archive.dat')
            json_path = os.path.join(directory, 'input sample.json')
            csv_path = os.path.join(directory, 'quoted.csv')

            rng = random.SystemRandom()
            marker = ''.join(rng.choice(string.ascii_uppercase) for _ in range(8))
            json_hash = 'AAAA' + marker[0] * 3 + '11' + marker[1] * 5
            csv_hash = marker[2] * 2 + ',,' + marker[3] * 4 + 'ZZZ'

            with open(json_path, 'w', encoding='utf-8') as handle:
                json.dump({
                    'metadata': {'config_hash': 'THIS_IS_A_DECOY'},
                    'description': 'another config_hash decoy',
                    'config_hash': json_hash
                }, handle, indent=2)

            with open(csv_path, 'w', encoding='utf-8', newline='') as handle:
                writer = csv.writer(handle)
                writer.writerow(['id', 'description', 'hash', 'status'])
                writer.writerow(['1', 'field, containing, commas', csv_hash, 'active'])
                writer.writerow(['2', 'second row', 'WRONG_SECOND_ROW', 'inactive'])

            write_ini(archive)
            completed = subprocess.run(
                ['python3', SCRIPT_PATH],
                input=json_path + '\n' + csv_path + '\n',
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10
            )
            assert completed.returncode == 0, completed.stderr
            assert os.path.isfile(archive), 'Tracker did not create the archive selected in tracker.ini'

            with open(archive, 'r', encoding='utf-8') as handle:
                actual = handle.readlines()

            expected = [
                f'{os.path.basename(json_path)}:{rle(json_hash)}\n',
                f'{os.path.basename(csv_path)}:{rle(csv_hash)}\n'
            ]
            assert actual == expected, f'Expected {expected!r}, got {actual!r}'
    finally:
        with open(INI_PATH, 'wb') as handle:
            handle.write(original_ini)


def test_tracker_requests_an_exclusive_archive_lock():
    with open(INI_PATH, 'rb') as handle:
        original_ini = handle.read()

    process = None
    lock_handle = None
    try:
        with tempfile.TemporaryDirectory(prefix='tracker-lock-test-') as directory:
            archive = os.path.join(directory, 'locked-archive.dat')
            input_path = os.path.join(directory, 'lock.json')
            value = 'QQQQRRSSSSS'

            with open(input_path, 'w', encoding='utf-8') as handle:
                json.dump({'config_hash': value}, handle)
            write_ini(archive)

            lock_handle = open(archive, 'a+', encoding='utf-8')
            # A shared lock permits another shared lock but blocks the required
            # exclusive lock, distinguishing LOCK_EX from LOCK_SH or no lock.
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_SH)

            process = subprocess.Popen(
                ['python3', SCRIPT_PATH],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            process.stdin.write(input_path + '\n')
            process.stdin.close()

            deadline = time.time() + 2.0
            while time.time() < deadline and process.poll() is None:
                time.sleep(0.05)
            assert process.poll() is None, 'Tracker wrote without waiting for an exclusive archive lock'

            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
            lock_handle.close()
            lock_handle = None

            process.wait(timeout=10)
            stderr = process.stderr.read()
            assert process.returncode == 0, stderr
            process = None

            with open(archive, 'r', encoding='utf-8') as handle:
                assert handle.read() == f'{os.path.basename(input_path)}:{rle(value)}\n'
    finally:
        if lock_handle is not None:
            try:
                fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
            finally:
                lock_handle.close()
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        with open(INI_PATH, 'wb') as handle:
            handle.write(original_ini)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
