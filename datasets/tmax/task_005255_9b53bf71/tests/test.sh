#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

import numpy as np

BASE = Path('/home/user/mc_sim')
AGGREGATE = BASE / 'aggregate.sh'
GENERATE = BASE / 'generate.py'
AVERAGED = BASE / 'averaged_signal.txt'
ANALYZE = BASE / 'analyze.sh'
SVD_OUTPUT = BASE / 'svd_top3.txt'


def run(path, timeout=30):
    return subprocess.run(
        [str(path)], cwd=str(BASE), check=True, timeout=timeout,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def read_nonempty_lines(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def expected_aggregate_from_generator():
    rows = []
    for idx in range(1, 101):
        output = subprocess.check_output(
            [str(GENERATE), str(idx)], text=True, timeout=10
        ).strip()
        fields = output.split(',')
        assert len(fields) == 101
        rows.append((int(fields[0]), [float(x) for x in fields[1:]]))

    sums = [0.0] * 100
    for _, values in sorted(rows, key=lambda row: row[0]):
        for column, value in enumerate(values):
            sums[column] += value
    return ','.join(f'{value:.15e}' for value in sums)


def expected_svd_text(values):
    matrix = np.asarray(values, dtype=float).reshape(10, 10)
    singular_values = np.linalg.svd(matrix, compute_uv=False)[:3]
    return [f'{value:.4f}' for value in singular_values]


def test_01_aggregate_sh_fixed():
    assert AGGREGATE.is_file(), f'File {AGGREGATE} does not exist.'
    assert os.access(AGGREGATE, os.X_OK), f'File {AGGREGATE} is not executable.'
    content = AGGREGATE.read_text()
    assert re.search(r'\bsort\b', content), (
        "aggregate.sh does not seem to use 'sort' to order the intermediate outputs."
    )


def test_02_averaged_signal_exists():
    assert AVERAGED.is_file(), f'File {AVERAGED} does not exist. Did you run aggregate.sh?'
    values = AVERAGED.read_text().strip().split(',')
    assert len(values) == 100, (
        f'Expected 100 values in averaged_signal.txt, found {len(values)}.'
    )


def test_03_analyze_sh_exists_and_executable():
    assert ANALYZE.is_file(), f'File {ANALYZE} does not exist.'
    assert os.access(ANALYZE, os.X_OK), f'File {ANALYZE} is not executable.'
    first_line = ANALYZE.read_text().splitlines()[0]
    assert first_line.startswith('#!') and 'bash' in first_line, 'analyze.sh must be a Bash script.'


def test_04_svd_top3_output():
    assert SVD_OUTPUT.is_file(), f'File {SVD_OUTPUT} does not exist. Did you run analyze.sh?'
    lines = read_nonempty_lines(SVD_OUTPUT)
    assert len(lines) == 3, f'Expected exactly 3 lines in svd_top3.txt, found {len(lines)}.'
    expected_values = ['119.2941', '36.3150', '33.6062']
    for i, (actual, expected) in enumerate(zip(lines, expected_values)):
        assert actual == expected, (
            f"Line {i+1} in svd_top3.txt is '{actual}', expected '{expected}'."
        )


def test_05_scripts_perform_sorted_aggregation_and_svd():
    backup = Path('/tmp/generate.py.verifier-backup')
    marker_dir = Path('/tmp/agg_verify_markers')
    shutil.copy2(GENERATE, backup)
    shutil.rmtree(marker_dir, ignore_errors=True)

    controlled_generator = r'''#!/usr/bin/env python3
import os
import sys
import time

idx = int(sys.argv[1])
marker_dir = '/tmp/agg_verify_markers'
os.makedirs(marker_dir, exist_ok=True)
open(os.path.join(marker_dir, str(idx)), 'w').close()

# This barrier requires the aggregation script to retain parallel execution.
if idx == 1:
    deadline = time.time() + 6.0
    while not os.path.exists(os.path.join(marker_dir, '2')):
        if time.time() > deadline:
            sys.exit(9)
        time.sleep(0.01)
    # Force run 1 to finish after later runs.
    time.sleep(0.6)

values = []
for column in range(100):
    if column % 2 == 0:
        # Numeric index order sums to 1; completion order sums to 0.
        value = 1e16 if idx == 1 else (-1e16 if idx == 2 else (1.0 if idx == 3 else 0.0))
    else:
        # Numeric index order sums to 0; lexicographic index order sums to 1.
        value = 1e16 if idx == 1 else (1.0 if idx == 2 else (-1e16 if idx == 10 else 0.0))
    values.append(f'{value:.15e}')
print(','.join([str(idx)] + values))
'''

    try:
        GENERATE.write_text(controlled_generator)
        os.chmod(GENERATE, 0o755)

        started = time.monotonic()
        run(AGGREGATE, timeout=12)
        elapsed = time.monotonic() - started
        assert elapsed < 5.0, 'aggregate.sh did not run generator invocations in parallel.'

        controlled_values = AVERAGED.read_text().strip().split(',')
        assert len(controlled_values) == 100
        expected_controlled = [1.0 if i % 2 == 0 else 0.0 for i in range(100)]
        assert [float(x) for x in controlled_values] == expected_controlled, (
            'aggregate.sh did not numerically sort complete rows by run_index before stripping the index and summing.'
        )
    finally:
        shutil.copy2(backup, GENERATE)
        backup.unlink(missing_ok=True)
        shutil.rmtree(marker_dir, ignore_errors=True)

    # Derive the correct aggregate directly from fresh generator executions.
    expected_aggregate = expected_aggregate_from_generator()
    run(AGGREGATE)
    first_result = AVERAGED.read_text().strip()
    run(AGGREGATE)
    second_result = AVERAGED.read_text().strip()
    assert first_result == second_result, 'Repeated aggregate.sh runs are not bit-for-bit reproducible.'
    assert first_result == expected_aggregate, 'aggregate.sh output is not the sorted run-index reduction.'

    # Execute analyze.sh on the real aggregate and compare against an independent SVD.
    run(ANALYZE)
    real_values = [float(x) for x in AVERAGED.read_text().strip().split(',')]
    assert read_nonempty_lines(SVD_OUTPUT) == expected_svd_text(real_values)

    # Exercise analyze.sh on a new, verifier-derived matrix to reject hardcoded output.
    rng = np.random.default_rng(20260911)
    probe = rng.normal(size=100) + np.linspace(-3.0, 4.0, 100)
    AVERAGED.write_text(','.join(f'{x:.17g}' for x in probe) + '\n')
    run(ANALYZE)
    probe_lines = read_nonempty_lines(SVD_OUTPUT)
    assert probe_lines == expected_svd_text(probe)
    assert all(re.fullmatch(r'\d+\.\d{4}', line) for line in probe_lines), (
        'Singular values must be written one per line with exactly four decimal places.'
    )

    # Leave the requested final artifacts generated from the real simulation.
    run(AGGREGATE)
    run(ANALYZE)
    final_values = [float(x) for x in AVERAGED.read_text().strip().split(',')]
    assert read_nonempty_lines(SVD_OUTPUT) == expected_svd_text(final_values)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
