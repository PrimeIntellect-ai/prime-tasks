#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = '/home/user/detector'
SOURCE = '/home/user/detector.c'
REFERENCE = [0.500, -0.200, 0.100, 0.800, 0.250]
THRESHOLD = 0.85


def run_detector(executable, path, timeout=5):
    return subprocess.run(
        [executable, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def cosine(row):
    dot = sum(a * b for a, b in zip(row, REFERENCE))
    row_norm = math.sqrt(sum(a * a for a in row))
    ref_norm = math.sqrt(sum(a * a for a in REFERENCE))
    return dot / (row_norm * ref_norm)


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The submitted detector is not a compiled ELF executable."


def test_clean_corpus():
    """Verify that all clean files are accepted (exit code 0)."""
    clean_dir = '/app/clean'
    clean_files = glob.glob(os.path.join(clean_dir, '*.csv'))
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}."

    failed_files = []
    for f in clean_files:
        result = run_detector(EXECUTABLE, f)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_evil_corpus():
    """Verify that all evil files are rejected (exit code 1)."""
    evil_dir = '/app/evil'
    evil_files = glob.glob(os.path.join(evil_dir, '*.csv'))
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}."

    failed_files = []
    for f in evil_files:
        result = run_detector(EXECUTABLE, f)
        if result.returncode != 1:
            failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def make_low_similarity_row(rng):
    while True:
        row = [rng.gauss(0.0, 1.0) for _ in range(5)]
        if sum(x * x for x in row) > 1e-8 and cosine(row) < 0.72:
            return row


def make_high_similarity_row(rng):
    while True:
        scale = rng.uniform(0.4, 3.0)
        row = [scale * x + rng.gauss(0.0, 0.08) for x in REFERENCE]
        if cosine(row) > 0.93:
            return row


def csv_text(rows):
    lines = ['id,f1,f2,f3,f4,f5']
    for i, row in enumerate(rows):
        lines.append(str(1000 + i) + ',' + ','.join(format(x, '.9g') for x in row))
    return '\n'.join(lines) + '\n'


def expected_from_csv(text):
    rows = text.strip().splitlines()[1:]
    for line in rows:
        values = [float(x) for x in line.split(',')[1:]]
        if cosine(values) >= THRESHOLD:
            return 1
    return 0


def test_source_build_and_content_derived_cases():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."

    with tempfile.TemporaryDirectory(prefix='detector_verify_') as td:
        rebuilt = os.path.join(td, secrets.token_hex(10))
        build = subprocess.run(
            ['gcc', '-O2', SOURCE, '-o', rebuilt, '-lm'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, "detector.c does not compile with gcc -O2 and -lm."
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
        cases = []
        for _ in range(10):
            count = rng.randint(3, 11)
            clean_rows = [make_low_similarity_row(rng) for _ in range(count)]
            cases.append(csv_text(clean_rows))

            mixed_rows = [make_low_similarity_row(rng) for _ in range(count)]
            mixed_rows.insert(rng.randrange(len(mixed_rows) + 1), make_high_similarity_row(rng))
            cases.append(csv_text(mixed_rows))
        rng.shuffle(cases)

        for text in cases:
            expected = expected_from_csv(text)
            assert expected in (0, 1)
            path = os.path.join(td, secrets.token_hex(16) + '.csv')

            for executable in (EXECUTABLE, rebuilt):
                with open(path, 'w', encoding='ascii', newline='') as f:
                    f.write(text)
                result = run_detector(executable, path)
                assert result.returncode == expected, (
                    f"{executable} returned {result.returncode}; expected {expected} "
                    "for a verifier-generated CSV."
                )
                assert result.stdout == b'' and result.stderr == b'', (
                    f"{executable} produced output, but the final detector must be silent."
                )


def test_exactly_one_argument_and_silence():
    no_arg = subprocess.run([EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    two_args = subprocess.run(
        [EXECUTABLE, '/dev/null', '/dev/null'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert no_arg.returncode != 0, "Detector accepted an invocation with no CSV argument."
    assert two_args.returncode != 0, "Detector accepted an invocation with two arguments."
    assert no_arg.stdout == b'' and no_arg.stderr == b''
    assert two_args.stdout == b'' and two_args.stderr == b''
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
