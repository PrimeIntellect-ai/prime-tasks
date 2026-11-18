#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = '/home/user/process_sensors_fixed.py'
DATA_DIR = '/home/user/sensor_data'
LOG_PATH = '/home/user/bad_files.txt'
AGGREGATE_PATH = '/home/user/final_aggregate.json'


def remove_outputs():
    for path in (LOG_PATH, AGGREGATE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_fixed_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'Fixed script exited with status {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )


def read_bad_files():
    assert os.path.exists(LOG_PATH), f'The log file {LOG_PATH} does not exist.'
    with open(LOG_PATH, 'r') as f:
        return set(line.strip() for line in f if line.strip())


def read_aggregate():
    assert os.path.exists(AGGREGATE_PATH), f'The output file {AGGREGATE_PATH} does not exist.'
    with open(AGGREGATE_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {AGGREGATE_PATH} is not valid JSON.')


def test_00_fixed_script_exists():
    assert os.path.exists(SCRIPT_PATH), f'The fixed script {SCRIPT_PATH} does not exist.'
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()
    assert 'concurrent.futures' in content, 'The fixed script must still use concurrent.futures to parallelize processing.'


def test_01_execute_fixed_script():
    remove_outputs()
    run_fixed_script()


def test_02_bad_files_log():
    bad_files = read_bad_files()
    expected_bad_files = {'sensor_98.json', 'sensor_99.json'}
    assert bad_files == expected_bad_files, f'Expected {LOG_PATH} to contain {expected_bad_files}, but got {bad_files}'


def test_03_final_aggregate():
    data = read_aggregate()
    assert 'total' in data, f"The key 'total' is missing from {AGGREGATE_PATH}."
    expected_total = 3000
    assert data['total'] == expected_total, f"Expected 'total' to be {expected_total}, but got {data['total']}."


def test_04_processes_runtime_generated_inputs():
    token = secrets.token_hex(12)
    created = []
    original_log = open(LOG_PATH, 'rb').read()
    original_aggregate = open(AGGREGATE_PATH, 'rb').read()

    try:
        for index in range(3):
            path = os.path.join(DATA_DIR, f'runtime_{token}_{index}.json')
            values = [secrets.randbelow(100000) + 1 for _ in range(index + 2)]
            with open(path, 'w') as f:
                json.dump({'id': token, 'values': values}, f)
            created.append(path)

        for index in range(2):
            path = os.path.join(DATA_DIR, f'corrupt_{token}_{index}.json')
            with open(path, 'w') as f:
                f.write('{"values": [1, 2,')
            created.append(path)

        expected_total = 0
        expected_bad_files = set()
        for path in glob.glob(os.path.join(DATA_DIR, '*.json')):
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
            except json.JSONDecodeError:
                expected_bad_files.add(os.path.basename(path))
            else:
                expected_total += sum(data['values'])

        remove_outputs()
        run_fixed_script()

        bad_files = read_bad_files()
        assert bad_files == expected_bad_files, (
            f'Expected dynamically derived bad files {expected_bad_files}, but got {bad_files}'
        )

        aggregate = read_aggregate()
        assert 'total' in aggregate, f"The key 'total' is missing from {AGGREGATE_PATH}."
        assert aggregate['total'] == expected_total, (
            f"Expected dynamically derived total {expected_total}, but got {aggregate['total']}."
        )
    finally:
        for path in created:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        with open(AGGREGATE_PATH, 'wb') as f:
            f.write(original_aggregate)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
