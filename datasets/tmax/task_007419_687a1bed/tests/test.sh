#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess

import pytest

APP = '/home/user/app'
SOURCE = os.path.join(APP, 'aggregator.c')
BINARY = os.path.join(APP, 'aggregator_fixed')
RESOLUTION = os.path.join(APP, 'resolution.txt')
DATA_FILES = [os.path.join(APP, 'data', f'region{i}.txt') for i in range(1, 5)]
SUBMITTED_COPY = '/tmp/aggregator_fixed.submitted'


def compute_expected_sum():
    """Compute the expected sum of squares directly from the data files."""
    total = 0
    for path in DATA_FILES:
        if os.path.exists(path):
            with open(path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        val = int(line)
                        total += val * val
    return total


def run_and_check(path, expected, runs):
    for i in range(runs):
        result = subprocess.run([path], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, (
            f'Execution failed on run {i + 1}: {result.stderr}'
        )
        assert result.stdout.strip() == str(expected), (
            f'Incorrect output on run {i + 1}: expected {expected}, '
            f'got {result.stdout.strip()!r}'
        )


@pytest.fixture(scope='session', autouse=True)
def preserve_original_data():
    saved = []
    for path in DATA_FILES:
        with open(path, 'rb') as f:
            saved.append(f.read())
    yield
    for path, content in zip(DATA_FILES, saved):
        with open(path, 'wb') as f:
            f.write(content)


def test_aggregator_fixed_exists_and_executable():
    """Verify that the fixed C program is compiled and executable."""
    assert os.path.isfile(BINARY), f'Compiled executable {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'File {BINARY} is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'aggregator_fixed must be a compiled ELF executable.'
    shutil.copy2(BINARY, SUBMITTED_COPY)


def test_resolution_txt_correct():
    """Verify that resolution.txt contains the correct aggregate value."""
    assert os.path.isfile(RESOLUTION), f'Resolution file {RESOLUTION} does not exist.'
    expected_sum = compute_expected_sum()
    with open(RESOLUTION, 'r') as f:
        content = f.read().strip()
    assert content == str(expected_sum), (
        f'Expected {expected_sum} in {RESOLUTION}, but found {content!r}.'
    )


def test_aggregator_fixed_no_race_condition():
    """Verify that running aggregator_fixed consistently produces the correct result."""
    assert os.path.isfile(BINARY), f'Compiled executable {BINARY} does not exist.'
    run_and_check(BINARY, compute_expected_sum(), 50)


def test_binary_was_built_from_aggregator_source():
    """Rebuild with the required command and require the submitted binary to match."""
    assert os.path.isfile(SOURCE), f'Source file {SOURCE} does not exist.'
    result = subprocess.run(
        ['gcc', '-pthread', '-o', 'aggregator_fixed', 'aggregator.c'],
        cwd=APP,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f'aggregator.c does not compile: {result.stderr}'

    def digest(path):
        h = hashlib.sha256()
        with open(path, 'rb') as f:
            for block in iter(lambda: f.read(65536), b''):
                h.update(block)
        return h.digest()

    assert digest(SUBMITTED_COPY) == digest(BINARY), (
        'Submitted aggregator_fixed was not produced from the current aggregator.c '
        'using the required gcc command.'
    )


def test_rebuilt_program_computes_changed_inputs_consistently():
    """Reject fixed-output artifacts and exercise the rebuilt source on derived answers."""
    cases = [
        (37, 3),
        (211, 7),
        (997, 11),
        (2003, 17),
        (4093, 23),
    ]
    for count, salt in cases:
        expected = 0
        for region, path in enumerate(DATA_FILES, 1):
            with open(path, 'w') as f:
                for j in range(count):
                    value = ((region * 29 + j * salt + j // 7) % 97) + 1
                    f.write(f'{value}\n')
                    expected += value * value
        run_and_check(BINARY, expected, 25)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
