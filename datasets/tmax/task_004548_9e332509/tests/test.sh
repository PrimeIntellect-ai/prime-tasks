#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import stat
import subprocess
from fractions import Fraction
from pathlib import Path

import pytest

PACKAGE = Path('/app/awk-stat-1.1')
BIN = PACKAGE / 'bin/awk-stat'
PIPELINE = Path('/home/user/feature_pipeline.sh')
REFERENCE = Path('/opt/oracle/reference_pipeline.sh')
HEADER = ['ID', 'Label', 'F1', 'F2', 'F3', 'F4', 'F5']


def run(cmd, **kwargs):
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('text', True)
    kwargs.setdefault('timeout', 15)
    return subprocess.run(cmd, **kwargs)


def test_awk_stat_fixed_and_built():
    assert BIN.exists(), f'Executable {BIN} not found. Did you fix the Makefile and run make?'
    assert os.access(BIN, os.X_OK), f'File {BIN} is not executable.'

    makefile = (PACKAGE / 'Makefile').read_text()
    assert 'src/header.awk' in makefile
    assert 'src/core.awk' in makefile
    assert 'missing_file.awk' not in makefile

    proc = run(['make', '-B'], cwd=PACKAGE)
    assert proc.returncode == 0, f'make failed: {proc.stderr}'
    assert BIN.exists() and os.access(BIN, os.X_OK)

    expected_binary = (PACKAGE / 'src/header.awk').read_bytes() + (PACKAGE / 'src/core.awk').read_bytes()
    assert BIN.read_bytes() == expected_binary, 'bin/awk-stat is not the concatenation of header.awk and core.awk'

    sample = Path('/tmp/awk_stat_check.csv')
    sample.write_text(
        'ID,Label,F1,F2,F3,F4,F5\n'
        '1,A,1,10,4,8,2\n'
        '2,B,3,10,8,6,4\n'
        '3,C,5,10,12,4,6\n'
    )
    proc = run([str(BIN), str(sample)])
    assert proc.returncode == 0, f'awk-stat failed: {proc.stderr}'

    actual = {}
    for line in proc.stdout.splitlines():
        parts = line.split()
        assert len(parts) == 2 and re.fullmatch(r'F[1-5]', parts[0]), \
            f'awk-stat must emit "ColumnName Variance", got {line!r}'
        actual[parts[0]] = float(parts[1])
    expected = {'F1': 4.0, 'F2': 0.0, 'F3': 16.0, 'F4': 4.0, 'F5': 4.0}
    assert actual.keys() == expected.keys()
    for name, value in expected.items():
        assert actual[name] == pytest.approx(value)


def test_feature_pipeline_exists_and_executable():
    assert PIPELINE.exists(), f'Script {PIPELINE} not found.'
    assert os.access(PIPELINE, os.X_OK), f'Script {PIPELINE} is not executable.'
    if REFERENCE.exists():
        assert PIPELINE.read_bytes() != REFERENCE.read_bytes(), 'Submission is identical to the shipped reference script.'


def write_csv(path, rows):
    with open(path, 'w', newline='') as f:
        f.write(','.join(HEADER) + '\n')
        for row in rows:
            f.write(','.join(map(str, row)) + '\n')


def expected_output(rows):
    variances = {}
    for column in range(2, 7):
        values = [Fraction(str(row[column])) for row in rows]
        mean = sum(values, Fraction(0)) / len(values)
        variance = sum((value - mean) ** 2 for value in values) / (len(values) - 1)
        variances[HEADER[column]] = variance

    chosen = sorted(variances, key=lambda name: (-variances[name], name))[:2]
    chosen_indices = sorted(HEADER.index(name) for name in chosen)
    keep = [0, 1] + chosen_indices

    lines = [','.join(HEADER[index] for index in keep)]
    for row in sorted(rows, key=lambda item: int(item[0])):
        lines.append(','.join(str(row[index]) for index in keep))
    return '\n'.join(lines) + '\n'


def assert_pipeline(path, rows):
    write_csv(path, rows)
    proc = run([str(PIPELINE), str(path)])
    assert proc.returncode == 0, f'Pipeline failed for {path}: {proc.stderr}'
    assert proc.stdout == expected_output(rows), (
        f'Output mismatch for input:\n{path.read_text()}\n'
        f'Expected:\n{expected_output(rows)}\nActual:\n{proc.stdout}'
    )


def test_accepts_exactly_one_argument(tmp_path):
    csv_path = tmp_path / 'args.csv'
    rows = [
        [2, 'A', 1, 2, 3, 4, 5],
        [1, 'B', 2, 4, 6, 8, 10],
    ]
    write_csv(csv_path, rows)
    assert run([str(PIPELINE)]).returncode != 0, 'Pipeline must reject zero arguments.'
    assert run([str(PIPELINE), str(csv_path), str(csv_path)]).returncode != 0, 'Pipeline must reject more than one argument.'


def test_pipeline_invokes_repaired_awk_stat(tmp_path):
    csv_path = tmp_path / 'instrumented.csv'
    rows = [
        [30, 'A', 0, 5, 3, 100, 9],
        [10, 'B', 1, 7, 3, 0, 8],
        [20, 'C', 2, 9, 3, 50, 7],
    ]
    write_csv(csv_path, rows)

    saved = tmp_path / 'awk-stat.real'
    marker = tmp_path / 'awk-stat.called'
    shutil.copy2(BIN, saved)
    wrapper = f'#!/bin/sh\n: > {str(marker)!r}\nexec {str(saved)!r} "$@"\n'
    BIN.write_text(wrapper)
    BIN.chmod(BIN.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    try:
        proc = run([str(PIPELINE), str(csv_path)])
        assert proc.returncode == 0, f'Pipeline failed: {proc.stderr}'
        assert marker.exists(), 'Pipeline did not invoke /app/awk-stat-1.1/bin/awk-stat.'
        assert proc.stdout == expected_output(rows)
    finally:
        shutil.copy2(saved, BIN)


def test_ties_and_original_feature_order(tmp_path):
    # F1, F2, and F3 tie for highest variance, so alphabetical tie-breaking keeps F1 and F2.
    tie_rows = [
        [9, 'A', 0, 0, 0, 5, 5],
        [2, 'B', 10, 10, 10, 5, 5],
        [6, 'C', 20, 20, 20, 5, 5],
    ]
    assert_pipeline(tmp_path / 'ties.csv', tie_rows)

    # F2 and F4 have the highest variances and must appear in their input-relative order.
    order_rows = [
        [50, 'A', 1, 0, 4, 100, 7],
        [3, 'B', 2, 20, 5, 0, 8],
        [21, 'C', 3, 40, 6, 50, 9],
        [8, 'D', 4, 60, 7, 150, 10],
    ]
    assert_pipeline(tmp_path / 'order.csv', order_rows)


def test_fuzz_equivalence_to_independent_computation(tmp_path):
    rng = random.SystemRandom()
    labels = ['A', 'B', 'C', 'D', 'E']

    for case in range(50):
        count = rng.randint(10, 100)
        ids = rng.sample(range(1, 100000), count)
        rows = []
        for index in range(count):
            rows.append([
                ids[index],
                rng.choice(labels),
                rng.randint(0, 100000),
                rng.randint(0, 100000),
                rng.randint(0, 100000),
                rng.randint(0, 100000),
                rng.randint(0, 100000),
            ])
        assert_pipeline(tmp_path / f'fuzz_{case}.csv', rows)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
