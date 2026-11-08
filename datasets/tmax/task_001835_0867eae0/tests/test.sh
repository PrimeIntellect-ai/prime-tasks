#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

ROOT = Path('/home/user/calc_metrics')
SOURCE = ROOT / 'calc_metrics.c'
BINARY = ROOT / 'calc_metrics'
OUTPUT = ROOT / 'output_fixed.csv'

EXPECTED_NIGHTLY = """1,2.0000
2,0.0000
3,0.0000
4,4.0000
5,0.2500
6,0.0000
---HISTOGRAM---
0:4
1:0
2:1
3:0
4:1
5:0
6:0
7:0
8:0
9:0"""


def normalized_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def assert_expected_output(path, expected):
    assert path.is_file(), f"Expected output file '{path}' was not created."
    actual_lines = normalized_lines(path.read_text())
    expected_lines = normalized_lines(expected)
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines, but got {len(actual_lines)}."
    )
    for i, (actual, wanted) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == wanted, (
            f"Line {i + 1} is incorrect. Expected '{wanted}', got '{actual}'."
        )


def run_program(program, input_path, expected):
    with tempfile.TemporaryDirectory(prefix='calc_metrics_run_') as td:
        output_path = Path(td) / 'result.csv'
        result = subprocess.run(
            [str(program), str(input_path), str(output_path)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{program} exited with status {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert_expected_output(output_path, expected)


@pytest.fixture(scope='session')
def compiled_source(tmp_path_factory):
    assert SOURCE.is_file(), f"The required source file '{SOURCE}' does not exist."
    build_dir = tmp_path_factory.mktemp('source_build')
    executable = build_dir / 'calc_metrics_from_source'
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(SOURCE), '-o', str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"calc_metrics.c does not compile successfully: {result.stderr}"
    )
    return executable


def test_output_fixed_csv_exists():
    assert OUTPUT.is_file(), (
        f"The output file '{OUTPUT}' does not exist. Did you run the compiled "
        "program and save the output?"
    )


def test_output_fixed_csv_contents():
    with open(OUTPUT, 'r') as f:
        content = f.read().strip()

    expected_lines = normalized_lines(EXPECTED_NIGHTLY)
    actual_lines = normalized_lines(content)

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in output_fixed.csv, but got "
        f"{len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} of output_fixed.csv is incorrect. Expected "
            f"'{expected}', got '{actual}'."
        )


def test_recompiled_program_exists_and_is_elf():
    assert BINARY.is_file(), f"The recompiled program '{BINARY}' does not exist."
    assert os.access(BINARY, os.X_OK), f"'{BINARY}' is not executable."
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"'{BINARY}' is not a compiled ELF program."


def test_source_and_recompiled_program_on_nightly(compiled_source):
    nightly = ROOT / 'nightly.csv'
    assert nightly.is_file(), f"The required input file '{nightly}' is missing."
    run_program(compiled_source, nightly, EXPECTED_NIGHTLY)
    run_program(BINARY, nightly, EXPECTED_NIGHTLY)


def test_required_edge_cases_on_unseen_input(compiled_source, tmp_path):
    base = secrets.randbelow(800000) + 100000
    cancel_value = secrets.randbelow(8) + 1
    repeated_value = secrets.randbelow(7) + 3

    records = [
        (base, 0, None),
        (base + 1, 2, [float(cancel_value), float(-cancel_value)]),
        (base + 2, 4, [float(repeated_value)] * 4),
        (base + 3, 2, [2.0, 4.0]),
        (base + 4, 2, [2.0, -2.0]),
    ]

    input_lines = []
    means = []
    for record_id, count, values in records:
        if values is None:
            input_lines.append(f"{record_id};{count}")
            mean = 0.0
        else:
            input_lines.append(
                f"{record_id};{count};" + ','.join(str(value) for value in values)
            )
            inverse_sum = sum(1.0 / value for value in values)
            mean = 0.0 if inverse_sum == 0.0 else count / inverse_sum
        means.append((record_id, mean))

    histogram = [0] * 10
    expected_lines = []
    for record_id, mean in means:
        expected_lines.append(f"{record_id},{mean:.4f}")
        bucket = int(mean) % 10
        histogram[bucket] += 1
    expected_lines.append('---HISTOGRAM---')
    expected_lines.extend(f"{bucket}:{count}" for bucket, count in enumerate(histogram))
    expected = '\n'.join(expected_lines)

    hidden_input = tmp_path / f'metrics_{secrets.token_hex(8)}.csv'
    hidden_input.write_text('\n'.join(input_lines) + '\n')

    run_program(compiled_source, hidden_input, expected)
    run_program(BINARY, hidden_input, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
