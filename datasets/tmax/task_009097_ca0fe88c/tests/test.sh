#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import subprocess
from pathlib import Path

import pytest

EXP = Path('/home/user/experiment')
TRUTH = EXP / 'truth.csv'
PREDS = EXP / 'preds.csv'
REPORT = EXP / 'metrics_report.txt'
EXECUTABLE = EXP / 'evaluate'
SOURCE = EXP / 'evaluate.c'
MAKEFILE = EXP / 'Makefile'

ORIGINAL_TRUTH = {
    1: 1.0,
    2: 0.0,
    3: 1.0,
    4: 0.0,
    5: 1.0,
}
ORIGINAL_PREDS = {
    3: 0.9,
    4: 0.2,
    1: 0.8,
    5: 0.4,
    2: 0.6,
}


def read_csv(path):
    data = {}
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['id', 'value'], f'{path} must have header id,value'
        for row in reader:
            data[int(row['id'])] = float(row['value'])
    return data


def expected_lines(truth_data, preds_data):
    matched_ids = set(truth_data).intersection(preds_data)
    assert matched_ids, 'No matching IDs found between truth and predictions.'

    sq_errors = []
    correct = 0
    for sample_id in matched_ids:
        truth = truth_data[sample_id]
        pred = preds_data[sample_id]
        sq_errors.append((truth - pred) ** 2)
        if (truth >= 0.5) == (pred >= 0.5):
            correct += 1

    count = len(matched_ids)
    mse = sum(sq_errors) / count
    accuracy = correct / count
    return [
        f'Total Samples: {count}',
        f'MSE: {mse:.4f}',
        f'Accuracy: {accuracy:.4f}',
    ]


def run_and_check(truth_data, preds_data):
    if REPORT.exists():
        REPORT.unlink()

    result = subprocess.run(
        [str(EXECUTABLE)], cwd=EXP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f'evaluate exited with {result.returncode}. stderr: {result.stderr}'
    )
    assert REPORT.is_file(), 'evaluate did not generate metrics_report.txt'

    content = REPORT.read_text().strip()
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    assert len(lines) == 3, (
        f'metrics_report.txt should have exactly 3 lines, but found {len(lines)}.'
    )
    expected = expected_lines(truth_data, preds_data)
    for index, (actual, wanted) in enumerate(zip(lines, expected), 1):
        assert actual == wanted, (
            f"Line {index} mismatch. Expected '{wanted}', got '{actual}'"
        )


@pytest.fixture(scope='session', autouse=True)
def build_submission():
    assert SOURCE.is_file(), 'evaluate.c is missing.'
    assert MAKEFILE.is_file(), 'Makefile is missing.'

    source_text = SOURCE.read_text()
    assert re.search(r'\bgsl_stats_mean\s*\(', source_text), (
        'evaluate.c must compute the MSE using gsl_stats_mean.'
    )
    assert re.search(r'\bgsl_vector_alloc\s*\(', source_text), (
        'evaluate.c must allocate a GSL vector for the squared errors.'
    )
    assert 'evaluate.c' in MAKEFILE.read_text(), (
        'The Makefile must build evaluate from evaluate.c.'
    )

    if EXECUTABLE.exists() or EXECUTABLE.is_symlink():
        EXECUTABLE.unlink()
    if REPORT.exists():
        REPORT.unlink()

    result = subprocess.run(
        ['make', '-B', 'evaluate'], cwd=EXP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f'make failed. stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert EXECUTABLE.is_file(), "The compiled executable 'evaluate' does not exist. Did you run make?"
    assert os.access(EXECUTABLE, os.X_OK), "The file 'evaluate' is not executable."

    linked = subprocess.run(
        ['ldd', str(EXECUTABLE)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert linked.returncode == 0 and re.search(r'libgsl\.so', linked.stdout), (
        'The Makefile-built evaluate executable is not linked against GSL.'
    )

    symbols = subprocess.run(
        ['nm', '-D', str(EXECUTABLE)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert symbols.returncode == 0 and re.search(r'\bgsl_stats_mean(?:@|\s|$)', symbols.stdout), (
        'The compiled executable does not call gsl_stats_mean.'
    )


def test_executable_exists():
    assert EXECUTABLE.is_file(), "The compiled executable 'evaluate' does not exist. Did you run make?"
    assert os.access(EXECUTABLE, os.X_OK), "The file 'evaluate' is not executable."


def test_metrics_report():
    assert TRUTH.is_file(), 'truth.csv is missing.'
    assert PREDS.is_file(), 'preds.csv is missing.'

    truth_data = read_csv(TRUTH)
    preds_data = read_csv(PREDS)
    assert truth_data == ORIGINAL_TRUTH, 'truth.csv was modified.'
    assert preds_data == ORIGINAL_PREDS, 'preds.csv was modified.'

    run_and_check(truth_data, preds_data)


def test_pipeline_on_hidden_join_case():
    truth_backup = TRUTH.read_bytes()
    preds_backup = PREDS.read_bytes()
    rng = random.SystemRandom()

    truth_rows = []
    for sample_id in range(101, 114):
        value = rng.uniform(0.03, 0.97)
        truth_rows.append((sample_id, float(f'{value:.8f}')))

    matched_ids = [row[0] for row in truth_rows]
    rng.shuffle(matched_ids)
    matched_ids = matched_ids[:9]

    preds_rows = []
    for sample_id in matched_ids:
        value = rng.uniform(0.03, 0.97)
        preds_rows.append((sample_id, float(f'{value:.8f}')))
    preds_rows.extend([
        (901, float(f'{rng.uniform(0.03, 0.97):.8f}')),
        (902, float(f'{rng.uniform(0.03, 0.97):.8f}')),
    ])
    rng.shuffle(truth_rows)
    rng.shuffle(preds_rows)

    try:
        with open(TRUTH, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'value'])
            writer.writerows(truth_rows)
        with open(PREDS, 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'value'])
            writer.writerows(preds_rows)

        run_and_check(read_csv(TRUTH), read_csv(PREDS))
    finally:
        TRUTH.write_bytes(truth_backup)
        PREDS.write_bytes(preds_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
