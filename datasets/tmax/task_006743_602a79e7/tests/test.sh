#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/train_metrics.csv "$backup_dir/train_metrics.csv"
cp /home/user/test_metrics.csv "$backup_dir/test_metrics.csv"
cp /home/user/metadata.csv "$backup_dir/metadata.csv"
if [ -e /home/user/test_ci.txt ]; then
    cp /home/user/test_ci.txt "$backup_dir/test_ci.txt"
    touch "$backup_dir/had_ci"
fi
cleanup() {
    cp "$backup_dir/train_metrics.csv" /home/user/train_metrics.csv
    cp "$backup_dir/test_metrics.csv" /home/user/test_metrics.csv
    cp "$backup_dir/metadata.csv" /home/user/metadata.csv
    if [ -e "$backup_dir/had_ci" ]; then
        cp "$backup_dir/test_ci.txt" /home/user/test_ci.txt
    else
        rm -f /home/user/test_ci.txt
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import re
import subprocess

CI_FILE = '/home/user/test_ci.txt'
BINARY = '/home/user/etl_pipeline'
SOURCE = '/home/user/etl_pipeline.cpp'
COMPILED_SOURCE = '/tmp/etl_pipeline_from_source'


def get_expected_ci():
    def read_csv(filepath):
        data = []
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                data.append(row)
        return data

    train = read_csv('/home/user/train_metrics.csv')
    test = read_csv('/home/user/test_metrics.csv')
    meta = read_csv('/home/user/metadata.csv')

    meta_ids = {row['experiment_id'] for row in meta}

    train_losses = [float(row['loss_score']) for row in train if row['experiment_id'] in meta_ids]
    test_losses = [float(row['loss_score']) for row in test if row['experiment_id'] in meta_ids]

    assert len(train_losses) > 0, "No valid training data found after join."
    assert len(test_losses) > 0, "No valid test data found after join."

    train_mean = sum(train_losses) / len(train_losses)
    train_sq_sum = sum((x - train_mean) ** 2 for x in train_losses)
    train_std = math.sqrt(train_sq_sum / len(train_losses))
    assert train_std > 0, "Training standard deviation is zero."

    test_norm = [(x - train_mean) / train_std for x in test_losses]

    test_norm_mean = sum(test_norm) / len(test_norm)
    test_norm_sq_sum = sum((x - test_norm_mean) ** 2 for x in test_norm)
    test_norm_std = math.sqrt(test_norm_sq_sum / len(test_norm))

    margin = 1.96 * (test_norm_std / math.sqrt(len(test_norm)))
    return test_norm_mean - margin, test_norm_mean + margin


def read_and_check_ci(expected_lower, expected_upper):
    assert os.path.exists(CI_FILE), \
        f"The output file {CI_FILE} does not exist. Did you run the C++ pipeline and output to the correct path?"

    with open(CI_FILE, 'r') as f:
        content = f.read().strip()

    match = re.match(r'^\[\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\]$', content)
    assert match, \
        f"Output format in {CI_FILE} is incorrect. Expected format '[lower_bound, upper_bound]', got: '{content}'"

    actual_lower, actual_upper = float(match.group(1)), float(match.group(2))
    assert math.isclose(actual_lower, expected_lower, abs_tol=1e-3), \
        f"Lower bound {actual_lower} does not match expected {expected_lower:.4f}. Check your normalization and CI logic."
    assert math.isclose(actual_upper, expected_upper, abs_tol=1e-3), \
        f"Upper bound {actual_upper} does not match expected {expected_upper:.4f}. Check your normalization and CI logic."


def run_and_check(executable):
    expected = get_expected_ci()
    if os.path.exists(CI_FILE):
        os.remove(CI_FILE)
    result = subprocess.run([executable], cwd='/home/user', stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, \
        f"Pipeline {executable} exited with code {result.returncode}. stderr: {result.stderr}"
    read_and_check_ci(*expected)


def test_pipeline_binary_exists():
    assert os.path.exists(BINARY), \
        f"Compiled binary {BINARY} does not exist. Did you compile the code as instructed?"
    assert os.path.isfile(BINARY), f"{BINARY} is not a regular file."
    assert os.access(BINARY, os.X_OK), f"The file {BINARY} is not executable."
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY} is not a compiled ELF binary."


def test_ci_output_exists_and_correct():
    # Re-run the submitted artifact so a precomputed text file cannot satisfy the test.
    run_and_check(BINARY)


def write_case(case_number, rng):
    train_ids = [10000 + case_number * 100 + i for i in range(12)]
    test_ids = [20000 + case_number * 100 + i for i in range(10)]
    train_kept = {x for i, x in enumerate(train_ids) if i not in (1, 8)}
    test_kept = {x for i, x in enumerate(test_ids) if i not in (2, 7)}

    base = rng.uniform(-30.0, 40.0)
    scale = rng.uniform(0.4, 7.0)
    train_shape = [-2.7, -1.8, -1.1, -0.4, 0.0, 0.35, 0.9, 1.4, 2.2, 2.8, 3.5, 4.1]
    test_shape = [-1.3, -0.2, 0.4, 1.0, 1.8, 2.7, 3.4, 4.0, 5.2, 6.1]
    train_values = [base + scale * x + rng.uniform(-0.08, 0.08) for x in train_shape]
    test_values = [base + scale * x + rng.uniform(-0.08, 0.08) for x in test_shape]

    # Values omitted by the metadata join are deliberately extreme.
    train_values[1] = base + 1000.0 * scale
    train_values[8] = base - 900.0 * scale
    test_values[2] = base + 1200.0 * scale
    test_values[7] = base - 1100.0 * scale

    with open('/home/user/train_metrics.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['experiment_id', 'loss_score'])
        for experiment_id, loss in zip(train_ids, train_values):
            writer.writerow([experiment_id, f'{loss:.8f}'])

    with open('/home/user/test_metrics.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['experiment_id', 'loss_score'])
        for experiment_id, loss in zip(test_ids, test_values):
            writer.writerow([experiment_id, f'{loss:.8f}'])

    metadata_ids = list(train_kept | test_kept)
    rng.shuffle(metadata_ids)
    with open('/home/user/metadata.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['experiment_id', 'duration_seconds'])
        for experiment_id in metadata_ids:
            writer.writerow([experiment_id, rng.randint(60, 3600)])


def test_binary_and_modified_cpp_on_unseen_inputs():
    assert os.path.isfile(SOURCE), f"The required source file {SOURCE} does not exist."
    compile_result = subprocess.run(
        ['g++', '-O3', '-std=c++17', SOURCE, '-o', COMPILED_SOURCE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert compile_result.returncode == 0, \
        f"Modified C++ source does not compile: {compile_result.stderr}"

    rng = random.SystemRandom()
    for case_number in range(3):
        write_case(case_number, rng)
        run_and_check(BINARY)
        run_and_check(COMPILED_SOURCE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
