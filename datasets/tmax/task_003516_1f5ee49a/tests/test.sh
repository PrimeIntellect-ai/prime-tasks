#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

FILTER = '/home/user/filter'
SOURCE = '/home/user/filter.c'
CSV_PATH = '/home/user/timeseries.csv'
PLOT_PATH = '/home/user/plot.png'
ALPHA = 0.85
BETA = 0.17
DT = 0.1


def run_filter(executable, path):
    try:
        return subprocess.run(
            [executable, path], capture_output=True, timeout=10
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f'{executable} did not converge within 10 seconds')


def test_filter_executable_exists():
    """Test that the compiled filter executable exists."""
    assert os.path.isfile(FILTER), "/home/user/filter executable is missing."
    assert os.access(FILTER, os.X_OK), "/home/user/filter is not executable."
    with open(FILTER, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/filter is not a compiled ELF executable."


def test_filter_source_exists_and_compiles():
    assert os.path.isfile(SOURCE), "/home/user/filter.c is missing."
    text = open(SOURCE, encoding='utf-8', errors='replace').read()
    assert text.strip(), "/home/user/filter.c is empty."

    numbers = []
    for token in re.findall(r'(?<![A-Za-z_])(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?', text):
        try:
            numbers.append(float(token))
        except ValueError:
            pass
    for expected, name in [(ALPHA, 'alpha'), (BETA, 'beta'), (DT, 'Euler time step'), (1e-5, 'convergence tolerance'), (250.0, 'safety threshold')]:
        assert any(math.isclose(v, expected, rel_tol=1e-9, abs_tol=1e-12) for v in numbers), \
            f'/home/user/filter.c does not contain the required {name} value {expected}.'

    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', SOURCE, '-lm', '-o', '/tmp/filter_from_source'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f'/home/user/filter.c does not compile:\n{result.stderr}'


def test_timeseries_csv_exists_and_is_euler_output_for_sample():
    """Test that timeseries.csv exists and contains the requested Euler trajectory."""
    assert os.path.isfile(CSV_PATH), "/home/user/timeseries.csv is missing."
    rows = []
    with open(CSV_PATH, newline='', encoding='utf-8', errors='replace') as f:
        for raw in csv.reader(f):
            if not raw or all(not field.strip() for field in raw):
                continue
            assert len(raw) >= 2, 'timeseries.csv must contain t,y columns.'
            try:
                point = (float(raw[0].strip()), float(raw[1].strip()))
            except ValueError:
                assert not rows, 'timeseries.csv contains a malformed nonnumeric row.'
                continue
            assert all(math.isfinite(v) for v in point), 'timeseries.csv contains non-finite values.'
            rows.append(point)

    assert len(rows) >= 100, 'timeseries.csv does not contain a complete numerical trajectory.'
    sample_gc = 18
    first_t, first_y = rows[0]
    if math.isclose(first_t, 0.0, abs_tol=1e-7):
        assert math.isclose(first_y, 0.0, abs_tol=1e-7), 'The trajectory must start at y(0)=0.'
    else:
        expected_first = DT * ALPHA * sample_gc
        assert math.isclose(first_t, DT, abs_tol=1e-7)
        assert math.isclose(first_y, expected_first, rel_tol=1e-5, abs_tol=2e-5), \
            'The first recorded point is not the first Forward Euler step.'

    for (t0, y0), (t1, y1) in zip(rows, rows[1:]):
        assert math.isclose(t1 - t0, DT, rel_tol=1e-7, abs_tol=1e-7), \
            'timeseries.csv does not use dt=0.1.'
        expected_y = y0 + DT * (ALPHA * sample_gc - BETA * y0)
        assert math.isclose(y1, expected_y, rel_tol=2e-6, abs_tol=2e-4), \
            'timeseries.csv is not a Forward Euler solution using the extracted parameters.'

    assert abs(rows[-1][1] - rows[-2][1]) < 1.1e-5, \
        'The trajectory was not run to the required convergence tolerance.'
    assert math.isclose(rows[-1][1], ALPHA * sample_gc / BETA, abs_tol=0.001), \
        'The converged sample steady state is incorrect.'


def test_plot_png_exists_and_is_valid():
    """Test that plot.png exists and is a nontrivial valid PNG image."""
    assert os.path.isfile(PLOT_PATH), "/home/user/plot.png is missing."
    with open(PLOT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', '/home/user/plot.png is not a PNG file.'
    result = subprocess.run(
        ['identify', '-format', '%w %h %[colors]', PLOT_PATH], capture_output=True, text=True
    )
    assert result.returncode == 0, f'/home/user/plot.png is not a valid image: {result.stderr}'
    width, height, colors = map(int, result.stdout.split())
    assert width >= 100 and height >= 100 and colors > 1, \
        '/home/user/plot.png must be a nontrivial visualization.'


def test_adversarial_corpus():
    """Test that the filter correctly accepts clean sequences and rejects evil sequences."""
    executable = FILTER
    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.fasta')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.fasta')]

    clean_failures = []
    for f in clean_files:
        if run_filter(executable, f) != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        if run_filter(executable, f) != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_failures)}")
    assert not clean_failures and not evil_failures, " | ".join(error_msgs)


def make_fasta(path, gc_count, rng):
    sequence = list('GC' * (gc_count // 2) + ('g' if gc_count % 2 else '') + 'AaTtN' * 11)
    rng.shuffle(sequence)
    split = len(sequence) // 2
    chunks = [sequence[:split], sequence[split:]]
    with open(path, 'w', newline='') as f:
        f.write('>header_GCGC_must_be_ignored_' + secrets.token_hex(8) + '\n')
        for i, chunk in enumerate(chunks):
            if i:
                f.write('>second_header_CCGG_also_ignored\n')
            for start in range(0, len(chunk), 13):
                f.write(''.join(chunk[start:start + 13]) + '\n')


def test_unpredictable_generated_fastas_against_both_binaries():
    """Exercise unseen filenames and contents whose answers are independently derived."""
    assert os.path.isfile('/tmp/filter_from_source')
    rng = random.SystemRandom()
    counts = [0, 1, 7, 37, 49, 50, 51, 52, 73, rng.randint(80, 160)]
    rng.shuffle(counts)

    with tempfile.TemporaryDirectory(prefix='fasta_hidden_') as directory:
        cases = []
        for count in counts:
            path = os.path.join(directory, secrets.token_hex(12) + '.data')
            make_fasta(path, count, rng)
            steady_state = ALPHA * count / BETA
            expected = 1 if steady_state > 250.0 else 0
            cases.append((path, count, expected))

        for executable in [FILTER, '/tmp/filter_from_source']:
            for path, count, expected in cases:
                actual = run_filter(executable, path)
                assert actual == expected, \
                    f'{executable} returned {actual} for an unseen FASTA with {count} GC bases; expected {expected}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
