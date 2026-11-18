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
import time

DATASET = '/home/user/dataset.csv'
SOURCE = '/home/user/ml_pipeline.cpp'
EXECUTABLE = '/home/user/ml_pipeline'
REPORT = '/home/user/report.txt'

MODELS = [
    {'id': 1, 'w': 1.2e-10, 'b': 0.5},
    {'id': 2, 'w': 1.5e-10, 'b': -0.2},
    {'id': 3, 'w': 1.3e-10, 'b': 0.1},
]


def truncating_mean(total, count):
    return total // count if total >= 0 else -((-total) // count)


def expected_from_dataset(path):
    valid_f1_sum = 0
    valid_count = 0
    rows = []

    with open(path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            f1_str = row['f1']
            y = float(row['y'])
            if f1_str == 'NaN':
                rows.append({'f1': None, 'y': y})
            else:
                f1_val = int(f1_str)
                valid_f1_sum += f1_val
                valid_count += 1
                rows.append({'f1': f1_val, 'y': y})

    assert valid_count > 0, 'No valid f1 values found in the dataset.'
    assert rows, 'Dataset contains no rows.'
    mean = truncating_mean(valid_f1_sum, valid_count)

    best_model = None
    best_mse = float('inf')
    for model in MODELS:
        mse_sum = 0.0
        for row in rows:
            f1 = mean if row['f1'] is None else row['f1']
            prediction = f1 * model['w'] + model['b']
            mse_sum += (prediction - row['y']) ** 2
        mse = mse_sum / len(rows)
        if mse < best_mse:
            best_mse = mse
            best_model = model['id']

    return mean, best_model, best_mse


def parse_and_check_report(expected):
    assert os.path.isfile(REPORT), f'File {REPORT} does not exist.'
    with open(REPORT, 'r') as f:
        report_content = f.read().strip().split('\n')

    assert len(report_content) == 4, \
        f'Report should contain exactly 4 lines, found {len(report_content)}.'

    match_mean = re.match(r'^Imputed Mean:\s*(-?\d+)$', report_content[0].strip())
    assert match_mean, \
        f"First line format incorrect. Expected 'Imputed Mean: <exact_integer_mean>', got: {report_content[0]}"
    reported_mean = int(match_mean.group(1))
    assert reported_mean == expected[0], \
        f'Imputed Mean is incorrect. Expected {expected[0]}, got {reported_mean}. Check for integer overflow or precision loss.'

    match_model = re.match(r'^Best Model:\s*(\d+)$', report_content[1].strip())
    assert match_model, \
        f"Second line format incorrect. Expected 'Best Model: <1, 2, or 3>', got: {report_content[1]}"
    reported_model = int(match_model.group(1))
    assert reported_model == expected[1], \
        f'Best Model is incorrect. Expected {expected[1]}, got {reported_model}.'

    match_mse = re.match(r'^Best MSE:\s*(\d+\.\d{4})$', report_content[2].strip())
    assert match_mse, \
        f"Third line format incorrect. Expected 'Best MSE: <MSE_rounded_to_4_decimal_places>', got: {report_content[2]}"
    reported_mse = match_mse.group(1)
    assert abs(float(reported_mse) - expected[2]) < 0.0002, \
        f'Best MSE is incorrect. Expected around {expected[2]:.4f}, got {reported_mse}.'

    match_time = re.match(r'^Benchmark Time:\s*(\d+(?:\.\d+)?)\s*ms$', report_content[3].strip())
    assert match_time, \
        f"Fourth line format incorrect. Expected 'Benchmark Time: <total_time_in_milliseconds> ms', got: {report_content[3]}"
    return float(match_time.group(1))


def run_pipeline_and_check():
    expected = expected_from_dataset(DATASET)
    if os.path.exists(REPORT):
        os.remove(REPORT)

    started = time.monotonic()
    result = subprocess.run(
        [EXECUTABLE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    elapsed_ms = (time.monotonic() - started) * 1000.0
    assert result.returncode == 0, \
        f'Compiled pipeline exited with code {result.returncode}. stderr: {result.stderr[-2000:]}'
    benchmark_ms = parse_and_check_report(expected)
    assert benchmark_ms <= elapsed_ms + 1000.0, \
        f'Reported benchmark time ({benchmark_ms} ms) exceeds the program wall time ({elapsed_ms:.3f} ms).'
    return benchmark_ms


def write_generated_dataset(path, count, target_model_id, seed):
    rng = random.Random(seed)
    base = (1 << 61) + rng.randrange(1_000_000, 9_000_000)
    raw = []
    valid = []
    for i in range(count):
        if i % 11 == 0:
            raw.append(None)
        else:
            value = base + rng.randint(-2_000_000, 2_000_000)
            raw.append(value)
            valid.append(value)

    mean = truncating_mean(sum(valid), len(valid))
    model = MODELS[target_model_id - 1]
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'f1', 'y'])
        for i, value in enumerate(raw):
            effective = mean if value is None else value
            noise = ((i % 17) - 8) * 0.001
            y = effective * model['w'] + model['b'] + noise
            writer.writerow([i, 'NaN' if value is None else value, repr(y)])


def test_source_is_compiled_executed_and_report_is_correct():
    assert os.path.isfile(DATASET), f'File {DATASET} does not exist.'
    assert os.path.isfile(SOURCE), f'File {SOURCE} does not exist.'
    assert os.path.getsize(SOURCE) > 0, f'File {SOURCE} is empty.'

    original_dataset = '/tmp/original_dataset.csv'
    shutil.copyfile(DATASET, original_dataset)

    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)
    compile_result = subprocess.run(
        ['g++', '-O3', '-std=c++17', SOURCE, '-o', EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, \
        f'ml_pipeline.cpp did not compile successfully: {compile_result.stderr[-4000:]}'
    assert os.path.isfile(EXECUTABLE), 'Compilation did not create /home/user/ml_pipeline.'
    assert os.access(EXECUTABLE, os.X_OK), 'Compiled pipeline is not executable.'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Compiled pipeline is not an ELF executable.'

    try:
        # Preserve all original report assertions, but obtain the report by running
        # the submitted artifact rather than trusting a pre-created file.
        original_time = run_pipeline_and_check()
        assert original_time >= 0.0

        # Exercise the program on verifier-created inputs so a hard-coded report
        # cannot pass. The large case also makes the required 1,000-pass benchmark
        # observably larger than the small case.
        seed = int.from_bytes(os.urandom(8), 'big')
        write_generated_dataset(DATASET, 2000, 1, seed)
        small_time = run_pipeline_and_check()

        write_generated_dataset(DATASET, 100000, 2, seed ^ 0x9E3779B97F4A7C15)
        large_time = run_pipeline_and_check()
        assert large_time >= 2.0, \
            f'Benchmark time {large_time} ms is not credible for 1,000 passes over 100,000 rows.'
        assert large_time > small_time * 3.0, \
            f'Benchmark does not scale with inference work: small={small_time} ms, large={large_time} ms.'
    finally:
        shutil.copyfile(original_dataset, DATASET)
        if os.path.isfile(EXECUTABLE):
            subprocess.run(
                [EXECUTABLE], cwd='/home/user', stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=30, check=False
            )

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
