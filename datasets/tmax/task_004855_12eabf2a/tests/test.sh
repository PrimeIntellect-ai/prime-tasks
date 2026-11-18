#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import struct
import subprocess
import tempfile

import pytest

HOME = '/home/user'
CONFIG_PATH = '/home/user/.local/share/sensor/default.conf'
REPORT_PATH = '/home/user/final_report.txt'
PROCESSOR_PATH = '/home/user/processor'
SOURCE_PATH = '/home/user/processor.cpp'
RUN_ALL_PATH = '/home/user/run_all.sh'
DATA_GLOB = '/home/user/sensor_data/file_*.dat'


def processor_env():
    env = os.environ.copy()
    env['HOME'] = HOME
    env.pop('SENSOR_CONF', None)
    return env


def expected_for_file(path):
    with open(path, 'rb') as f:
        raw = f.read()
    assert len(raw) % 2 == 0, f'Odd-sized sensor file: {path}'
    values = [v[0] for v in struct.iter_unpack('<h', raw)]
    assert values, f'Empty sensor file: {path}'
    mean = int(sum(values) / len(values))  # C++ integer division truncates toward zero.
    varsum = sum((v - mean) * (v - mean) for v in values)
    return f'{path} Mean:{mean} VarSum:{varsum}'


def run_processor(binary, path):
    result = subprocess.run(
        [binary, path], env=processor_env(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f'{binary} failed on {path} with code {result.returncode}: {result.stderr}'
    )
    assert 'Warning' not in result.stderr, (
        f'{binary} did not find the required default configuration: {result.stderr}'
    )
    assert result.stdout == expected_for_file(path) + '\n', (
        f'Incorrect processor output for {path}: {result.stdout!r}'
    )


# Original assertions.
def test_config_file_exists():
    assert os.path.isfile(CONFIG_PATH), f'Expected configuration file {CONFIG_PATH} to be created.'


def test_final_report_exists():
    assert os.path.isfile(REPORT_PATH), f'Expected final report {REPORT_PATH} to be created.'


def test_final_report_no_warnings():
    with open(REPORT_PATH, 'r') as f:
        content = f.read()
    assert 'Warning' not in content, "The final report contains 'Warning', which means the configuration file wasn't properly detected or placed."


def test_final_report_no_negative_varsum():
    with open(REPORT_PATH, 'r') as f:
        lines = f.readlines()
    for line in lines:
        if 'VarSum:-' in line:
            pytest.fail(f'Found a negative VarSum in the final report, which indicates the integer overflow was not fixed. Line: {line.strip()}')


def test_final_report_correct_varsum_for_extreme_file():
    expected_substring = 'file_00.dat Mean:0 VarSum:5400000000'
    with open(REPORT_PATH, 'r') as f:
        content = f.read()
    assert expected_substring in content, f"Expected to find '{expected_substring}' in {REPORT_PATH}. The overflow fix might be incorrect or the script was not run properly."


# Added completeness and artifact checks.
def test_config_file_is_empty():
    assert os.path.getsize(CONFIG_PATH) == 0, 'The discovered default configuration file must be empty.'


def test_compiled_processor_and_source_exist():
    assert os.path.isfile(SOURCE_PATH), 'processor.cpp is missing.'
    assert os.path.isfile(PROCESSOR_PATH), 'Compiled processor is missing.'
    assert os.access(PROCESSOR_PATH, os.X_OK), 'processor is not executable.'
    with open(PROCESSOR_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'processor must be a compiled ELF executable.'


def test_report_has_all_fifty_exact_results():
    paths = sorted(glob.glob(DATA_GLOB))
    assert len(paths) == 50, f'Expected 50 sensor files, found {len(paths)}.'
    with open(REPORT_PATH, 'r') as f:
        actual = f.read().splitlines()
    expected = [expected_for_file(path) for path in paths]
    assert len(actual) == 50, f'Expected exactly 50 report lines, found {len(actual)}.'
    assert actual == expected, 'final_report.txt does not contain the exact result for every sensor file.'


def test_run_all_current_output_matches_report():
    result = subprocess.run(
        [RUN_ALL_PATH], env=processor_env(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f'run_all.sh failed: {result.stderr}'
    assert 'Warning' not in result.stderr, f'run_all.sh produced a configuration warning: {result.stderr}'
    with open(REPORT_PATH, 'r') as f:
        report = f.read()
    assert result.stdout == report, 'run_all.sh output does not match final_report.txt.'


def test_binary_and_recompiled_source_on_derived_inputs():
    build = subprocess.run(
        ['g++', '-O2', SOURCE_PATH, '-o', '/tmp/processor_from_source'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f'processor.cpp does not compile: {build.stderr}'

    cases = [
        [30000, -30000, 30000, -30000, 30000, -30000],
        [32767, -32768, 32767, -32768, 12345, -23456, 0],
        [secrets.randbelow(65536) - 32768 for _ in range(37)],
    ]
    with tempfile.TemporaryDirectory(prefix='sensor_verify_') as directory:
        for index, values in enumerate(cases):
            path = os.path.join(directory, f'case_{index}.dat')
            with open(path, 'wb') as f:
                for value in values:
                    f.write(struct.pack('<h', value))
            run_processor(PROCESSOR_PATH, path)
            run_processor('/tmp/processor_from_source', path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
