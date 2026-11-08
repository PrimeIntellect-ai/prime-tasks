#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import secrets
import stat
import statistics
import subprocess
import tempfile

import pytest


def test_classifier_exists_and_executable():
    executable_path = '/home/user/classifier'
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."

    st = os.stat(executable_path)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"File {executable_path} is not executable."

    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"Executable {executable_path} is not an ELF binary."


def test_adversarial_corpus_classification():
    executable_path = '/home/user/classifier'
    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'

    clean_files = glob.glob(os.path.join(clean_dir, '*.csv'))
    evil_files = glob.glob(os.path.join(evil_dir, '*.csv'))

    assert len(clean_files) > 0, f"No clean CSV files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil CSV files found in {evil_dir}."

    failed_clean = []
    failed_evil = []

    for clean_file in clean_files:
        result = subprocess.run([executable_path, clean_file], capture_output=True, timeout=10)
        if result.returncode != 0:
            failed_clean.append((os.path.basename(clean_file), result.returncode))

    for evil_file in evil_files:
        result = subprocess.run([executable_path, evil_file], capture_output=True, timeout=10)
        if result.returncode != 1:
            failed_evil.append((os.path.basename(evil_file), result.returncode))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: " + ", ".join(f"{f} (exit {c})" for f, c in failed_clean))
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted. Offending files: " + ", ".join(f"{f} (exit {c})" for f, c in failed_evil))

    if error_messages:
        assert False, " | ".join(error_messages)


@pytest.fixture(scope='module')
def rebuilt_classifier():
    source = '/home/user/classifier.c'
    assert os.path.isfile(source), f"C source {source} does not exist."

    output = os.path.join(tempfile.mkdtemp(prefix='classifier-build-'), 'classifier')
    result = subprocess.run(
        ['gcc', '-O0', source, '-o', output, '-lgsl', '-lgslcblas', '-lm'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"classifier.c could not be compiled with GSL:\n{result.stderr}"

    with open(output, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Recompiled classifier is not an ELF binary."

    linked = subprocess.run(['ldd', output], capture_output=True, text=True, timeout=10)
    assert linked.returncode == 0 and 'libgsl' in linked.stdout, "Recompiled classifier is not linked to GSL."

    symbols = subprocess.run(['nm', '-D', output], capture_output=True, text=True, timeout=10)
    assert symbols.returncode == 0 and 'gsl_stats_sd' in symbols.stdout, "classifier.c does not use a GSL sample-standard-deviation routine."
    return output


def _make_scaled_values(rng, target_sd, count=100):
    raw = [rng.gauss(rng.uniform(-20.0, 20.0), rng.uniform(0.2, 30.0)) for _ in range(count)]
    mean = statistics.fmean(raw)
    centered = [x - mean for x in raw]
    current_sd = statistics.stdev(centered)
    offset = rng.uniform(-100.0, 100.0)
    return [offset + x * target_sd / current_sd for x in centered]


def test_hidden_generated_csvs(rebuilt_classifier):
    rng = random.Random(secrets.randbits(256))
    test_dir = tempfile.mkdtemp(prefix='waveform-check-')

    labels = [0] * 16 + [1] * 16
    rng.shuffle(labels)
    cases = []

    for expected in labels:
        if expected == 0:
            target_sd = rng.uniform(0.05, 10.40)
        else:
            target_sd = rng.uniform(10.60, 45.0)
        values = _make_scaled_values(rng, target_sd)
        name = secrets.token_hex(16) + '.csv'
        path = os.path.join(test_dir, name)
        with open(path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['time', 'amplitude'])
            for i, value in enumerate(values):
                writer.writerow([format(i / 99.0, '.17g'), format(value, '.17g')])
        actual_sd = statistics.stdev(float(format(v, '.17g')) for v in values)
        derived_expected = 1 if actual_sd > 10.5 else 0
        assert derived_expected == expected
        cases.append((path, derived_expected))

    boundary_path = os.path.join(test_dir, secrets.token_hex(16) + '.csv')
    with open(boundary_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['time', 'amplitude'])
        writer.writerow(['0.0', '-10.5'])
        writer.writerow(['0.5', '0.0'])
        writer.writerow(['1.0', '10.5'])
    assert statistics.stdev([-10.5, 0.0, 10.5]) == 10.5
    cases.append((boundary_path, 0))

    for executable in ['/home/user/classifier', rebuilt_classifier]:
        run_order = cases[:]
        rng.shuffle(run_order)
        failures = []
        for path, expected in run_order:
            result = subprocess.run([executable, path], capture_output=True, timeout=10)
            if result.returncode != expected:
                failures.append((os.path.basename(path), expected, result.returncode))
        assert not failures, f"Generated CSV classification failures for {executable}: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
