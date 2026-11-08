#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import secrets
import struct
import subprocess
import tempfile

import pytest

SOURCE = '/home/user/src/sensor_aggregator.cpp'
BINARY = '/home/user/bin/sensor_aggregator'
PIPELINE = '/home/user/run_pipeline.sh'
OUTPUT = '/home/user/pipeline_success.out'
LINE_RE = re.compile(r'^File: (.+) \| Mean: (-?(?:\d+(?:\.\d*)?|\.\d+)) \| StdDev: (-?(?:\d+(?:\.\d*)?|\.\d+))$')


def f32(value):
    return struct.unpack('f', struct.pack('f', float(value)))[0]


def expected_stats_from_text(values):
    parsed = [f32(v) for v in values]
    mean = sum(parsed) / len(parsed)
    variance = sum((v - mean) ** 2 for v in parsed) / len(parsed)
    return mean, math.sqrt(variance)


def run_aggregator(binary, path):
    result = subprocess.run([binary, path], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f'{binary} failed for {path}: {result.stderr}'
    assert 'Domain error' not in result.stdout + result.stderr
    assert 'std::runtime_error' not in result.stdout + result.stderr
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f'Expected one output line from {binary}, got: {result.stdout!r}'
    match = LINE_RE.fullmatch(lines[0])
    assert match, f'Output formatting was altered: {lines[0]!r}'
    assert match.group(1) == path, f'Output reported the wrong input path: {lines[0]!r}'
    return float(match.group(2)), float(match.group(3)), result.stdout


def assert_correct_stats(binary, path, values, mean_tolerance=0.12, stddev_tolerance=0.12):
    actual_mean, actual_stddev, _ = run_aggregator(binary, path)
    expected_mean, expected_stddev = expected_stats_from_text(values)
    assert math.isfinite(actual_mean) and math.isfinite(actual_stddev)
    assert actual_stddev >= 0.0
    assert abs(actual_mean - expected_mean) <= mean_tolerance, \
        f'Incorrect mean for {path}: expected {expected_mean}, got {actual_mean}'
    assert abs(actual_stddev - expected_stddev) <= stddev_tolerance, \
        f'Incorrect standard deviation for {path}: expected {expected_stddev}, got {actual_stddev}'


def test_pipeline_success_out_exists():
    assert os.path.isfile('/home/user/pipeline_success.out'), "/home/user/pipeline_success.out does not exist. Did you run the pipeline and save the output?"


def test_pipeline_success_out_content():
    with open('/home/user/pipeline_success.out', 'r') as f:
        content = f.read()

    assert "File: /home/user/logs/batch_3.csv | Mean:" in content, "The output for batch_3.csv is missing or incorrectly formatted. The pipeline might have crashed or the output format was altered."

    lines = [line.strip() for line in content.split('\n') if line.strip()]
    assert len(lines) == 4, f"Expected exactly 4 lines of output in /home/user/pipeline_success.out, but found {len(lines)}."


def test_no_errors_in_output():
    with open('/home/user/pipeline_success.out', 'r') as f:
        content = f.read()
    assert "Domain error" not in content, "The output still contains a 'Domain error'. The numerical instability was not fixed."
    assert "std::runtime_error" not in content, "The output contains a runtime error. The pipeline did not complete successfully."


def test_cpp_source_modified():
    with open('/home/user/src/sensor_aggregator.cpp', 'r') as f:
        content = f.read()

    vulnerable_line = "float variance = (sum_sq / values.size()) - (mean * mean);"
    assert vulnerable_line not in content, "The C++ source code still uses the naive variance formula. You need to implement a numerically stable method."


def test_source_compiles_and_installed_binary_exists():
    assert os.path.isfile(SOURCE), 'The required C++ source file is missing.'
    assert os.path.isfile(BINARY), 'The recompiled sensor_aggregator binary is missing.'
    assert os.access(BINARY, os.X_OK), 'The sensor_aggregator binary is not executable.'
    result = subprocess.run(
        ['g++', '-O2', SOURCE, '-o', '/tmp/sensor_aggregator_from_source'],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f'The submitted C++ source does not compile: {result.stderr}'


def test_pipeline_output_matches_actual_binary_results():
    paths = sorted(glob.glob('/home/user/logs/*.csv'))
    assert len(paths) == 4
    expected_output = ''
    for path in paths:
        with open(path) as f:
            values = [line.strip() for line in f if line.strip()]
        assert_correct_stats(BINARY, path, values)
        _, _, stdout = run_aggregator(BINARY, path)
        expected_output += stdout

    pipeline_result = subprocess.run([PIPELINE], text=True, capture_output=True, timeout=20)
    assert pipeline_result.returncode == 0, f'The pipeline still fails: {pipeline_result.stderr}'
    assert pipeline_result.stdout == expected_output, 'The pipeline output does not match execution of the aggregator on every log file.'
    with open(OUTPUT) as f:
        saved_output = f.read()
    assert saved_output == expected_output, 'pipeline_success.out is not the successful output produced by the current binary.'


def test_numerically_stable_calculation_on_unseen_inputs():
    assert os.path.isfile('/tmp/sensor_aggregator_from_source')
    rng = secrets.SystemRandom()
    binaries = [BINARY, '/tmp/sensor_aggregator_from_source']

    with tempfile.TemporaryDirectory(prefix='aggregator_hidden_') as directory:
        for case_index in range(5):
            base = rng.randrange(100000, 400001)
            offsets = [rng.randrange(-40, 41) / 4.0 for _ in range(11)]
            if max(offsets) == min(offsets):
                offsets[-1] += 1.0
            values = [format(base + offset, '.9g') for offset in offsets]
            path = os.path.join(directory, f'case_{case_index}_{secrets.token_hex(5)}.csv')
            with open(path, 'w') as f:
                f.write('\n'.join(values) + '\n')

            expected_mean, expected_stddev = expected_stats_from_text(values)
            assert expected_stddev > 0.0
            results = []
            for binary in binaries:
                assert_correct_stats(binary, path, values)
                mean, stddev, _ = run_aggregator(binary, path)
                results.append((mean, stddev))
            assert results[0] == results[1], 'The installed binary does not behave like the submitted source.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
