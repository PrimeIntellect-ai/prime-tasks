#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

import pytest

DATA_PATH = '/home/user/sensor_data.csv'
RESULT_PATH = '/home/user/result.json'
SOURCE_PATH = '/home/user/bootstrap_ci.c'
EXECUTABLE_PATH = '/home/user/bootstrap_ci'


def get_expected_values(path=DATA_PATH):
    valid_temps = []
    with open(path, 'r') as f:
        next(f)  # skip header
        for line in f:
            parts = line.rstrip('\n').split(',')
            if len(parts) >= 3:
                temp_str = parts[2]
                if temp_str != '' and temp_str != 'NA':
                    valid_temps.append(float(temp_str))

    N = len(valid_temps)
    assert N > 0
    original_mean = sum(valid_temps) / N

    seed = 42

    def my_rand():
        nonlocal seed
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        return seed

    bootstrap_means = []
    for _ in range(10000):
        b_sum = 0.0
        for _ in range(N):
            idx = my_rand() % N
            b_sum += valid_temps[idx]
        bootstrap_means.append(b_sum / N)

    bootstrap_means.sort()
    return original_mean, bootstrap_means[250], bootstrap_means[9750]


def check_result(expected):
    assert os.path.exists(RESULT_PATH), f'{RESULT_PATH} is missing.'
    with open(RESULT_PATH, 'r') as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{RESULT_PATH} does not contain valid JSON.')

    assert 'original_mean' in actual_json, "Missing 'original_mean' in result.json"
    assert 'ci_lower' in actual_json, "Missing 'ci_lower' in result.json"
    assert 'ci_upper' in actual_json, "Missing 'ci_upper' in result.json"

    orig, lower, upper = expected
    expected_orig = round(orig, 2)
    expected_lower = round(lower, 2)
    expected_upper = round(upper, 2)

    assert abs(actual_json['original_mean'] - expected_orig) < 0.01, \
        f"Expected original_mean around {expected_orig}, got {actual_json['original_mean']}"
    assert abs(actual_json['ci_lower'] - expected_lower) < 0.01, \
        f"Expected ci_lower around {expected_lower}, got {actual_json['ci_lower']}"
    assert abs(actual_json['ci_upper'] - expected_upper) < 0.01, \
        f"Expected ci_upper around {expected_upper}, got {actual_json['ci_upper']}"


def run_and_check(binary, expected):
    if os.path.exists(RESULT_PATH):
        os.unlink(RESULT_PATH)
    proc = subprocess.run([binary], cwd='/home/user', stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=30)
    assert proc.returncode == 0, \
        f'{binary} exited with status {proc.returncode}: {proc.stderr}'
    check_result(expected)


def test_c_source_exists():
    assert os.path.exists(SOURCE_PATH), 'Source file /home/user/bootstrap_ci.c is missing.'
    assert os.path.isfile(SOURCE_PATH), 'Source path is not a regular file.'


def test_executable_exists():
    assert os.path.exists(EXECUTABLE_PATH), 'Executable /home/user/bootstrap_ci is missing.'
    assert os.access(EXECUTABLE_PATH, os.X_OK), 'File /home/user/bootstrap_ci is not executable.'
    assert os.path.isfile(EXECUTABLE_PATH), 'Executable path is not a regular file.'
    with open(EXECUTABLE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'bootstrap_ci is not a compiled native executable.'


def test_result_json_is_generated_by_executable():
    expected = get_expected_values()
    run_and_check(EXECUTABLE_PATH, expected)


def test_source_and_executable_on_unseen_inputs():
    original_data = open(DATA_PATH, 'rb').read()
    original_result = open(RESULT_PATH, 'rb').read() if os.path.exists(RESULT_PATH) else None

    with tempfile.TemporaryDirectory(prefix='bootstrap_verify_') as td:
        rebuilt = os.path.join(td, 'bootstrap_ci_rebuilt')
        compile_proc = subprocess.run(
            ['gcc', '-O2', SOURCE_PATH, '-o', rebuilt, '-lm'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_proc.returncode == 0, \
            f'bootstrap_ci.c does not compile with gcc: {compile_proc.stderr}'

        rng = secrets.SystemRandom()
        fixtures = []
        for n in (23, 29, 31):
            values = [rng.randrange(-1500, 5501) / 100.0 for _ in range(n)]
            lines = ['timestamp,sensor_id,temperature,status\n']
            value_index = 0
            total_rows = n + 8
            for row in range(total_rows):
                if row in (1, 7, total_rows - 2):
                    temp = ''
                elif row in (3, 11, total_rows - 1):
                    temp = 'NA'
                elif value_index < n:
                    temp = f'{values[value_index]:.2f}'
                    value_index += 1
                else:
                    temp = 'NA'
                lines.append(f'{1700000000 + row},S{(row % 5) + 1},{temp},ok\n')
            fixtures.append(''.join(lines).encode())

        try:
            for fixture in fixtures:
                with open(DATA_PATH, 'wb') as f:
                    f.write(fixture)
                expected = get_expected_values()
                run_and_check(EXECUTABLE_PATH, expected)
                run_and_check(rebuilt, expected)
        finally:
            with open(DATA_PATH, 'wb') as f:
                f.write(original_data)
            if original_result is None:
                if os.path.exists(RESULT_PATH):
                    os.unlink(RESULT_PATH)
            else:
                with open(RESULT_PATH, 'wb') as f:
                    f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
