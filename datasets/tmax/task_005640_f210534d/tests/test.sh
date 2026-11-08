#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import subprocess


def read_input_csv(path):
    with open(path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = []
        for row in reader:
            parsed = []
            for x in row:
                value = x.strip()
                parsed.append(None if not value or value.lower() == 'nan' else float(value))
            data.append(parsed)
    return header, data


def calc_mean(col):
    vals = [x for x in col if x is not None]
    return sum(vals) / len(vals)


def calc_pop_std(col, mu):
    vals = [x for x in col if x is not None]
    return math.sqrt(sum((x - mu) ** 2 for x in vals) / len(vals))


def calc_sample_cov(col1, col2):
    mu1 = calc_mean(col1)
    mu2 = calc_mean(col2)
    return sum((x - mu1) * (y - mu2) for x, y in zip(col1, col2)) / (len(col1) - 1)


def compute_expected_data(input_path='/home/user/sensor_data.csv'):
    if not os.path.exists(input_path):
        return [], []

    header, data = read_input_csv(input_path)
    cols = list(map(list, zip(*data)))

    # 1. Impute
    for i in range(len(cols)):
        mu = calc_mean(cols[i])
        cols[i] = [x if x is not None else mu for x in cols[i]]

    # 2. Cap outliers
    for i in range(len(cols)):
        mu = calc_mean(cols[i])
        sigma = calc_pop_std(cols[i], mu)
        cols[i] = [max(mu - 2 * sigma, min(mu + 2 * sigma, x)) for x in cols[i]]

    # 3. Feature Engineering
    interaction = [t * p for t, p in zip(cols[0], cols[1])]
    cols.append(interaction)

    # 4. Standardize
    for i in range(len(cols)):
        mu = calc_mean(cols[i])
        sigma = calc_pop_std(cols[i], mu)
        cols[i] = [(x - mu) / sigma for x in cols[i]]

    # 5. Covariance
    cov_matrix = []
    for i in range(len(cols)):
        row = []
        for j in range(len(cols)):
            row.append(calc_sample_cov(cols[i], cols[j]))
        cov_matrix.append(row)

    processed_data = list(map(list, zip(*cols)))
    return processed_data, cov_matrix


def assert_outputs(expected_data, expected_cov):
    output_path = '/home/user/processed_data.csv'
    assert os.path.isfile(output_path), f'{output_path} is missing.'

    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['temp', 'pressure', 'humidity', 'temp_pressure_interaction'], 'Header is incorrect.'
        actual_data = [[float(x) for x in row] for row in reader]

    assert len(actual_data) == len(expected_data), 'Number of rows in processed data is incorrect.'
    for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_data)):
        assert len(actual_row) == len(expected_row), f'Number of columns in processed data row {i + 1} is incorrect.'
        for j, (actual_val, expected_val) in enumerate(zip(actual_row, expected_row)):
            assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
                f'Mismatch at row {i + 1}, col {j}: expected {expected_val:.4f}, got {actual_val:.4f}'

    output_path = '/home/user/cov_matrix.txt'
    assert os.path.isfile(output_path), f'{output_path} is missing.'
    with open(output_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == len(expected_cov), 'Number of rows in covariance matrix is incorrect.'
    for i, (line, expected_row) in enumerate(zip(lines, expected_cov)):
        actual_row = [float(x) for x in line.split()]
        assert len(actual_row) == len(expected_row), f'Number of columns in covariance matrix row {i} is incorrect.'
        for j, (actual_val, expected_val) in enumerate(zip(actual_row, expected_row)):
            assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
                f'Covariance mismatch at ({i}, {j}): expected {expected_val:.4f}, got {actual_val:.4f}'


def test_executable_exists():
    assert os.path.isfile('/home/user/etl_bin'), 'Executable /home/user/etl_bin is missing.'
    assert os.access('/home/user/etl_bin', os.X_OK), '/home/user/etl_bin is not executable.'
    with open('/home/user/etl_bin', 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/etl_bin is not a compiled executable.'


def test_source_exists():
    assert os.path.isfile('/home/user/etl.cpp'), 'Source file /home/user/etl.cpp is missing.'


def test_processed_data_csv():
    output_path = '/home/user/processed_data.csv'
    assert os.path.exists(output_path), f'{output_path} is missing.'
    expected_data, _ = compute_expected_data()

    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['temp', 'pressure', 'humidity', 'temp_pressure_interaction'], 'Header is incorrect.'
        actual_data = [[float(x) for x in row] for row in reader]

    assert len(actual_data) == len(expected_data), 'Number of rows in processed data is incorrect.'
    for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_data)):
        assert len(actual_row) == len(expected_row), f'Number of columns in processed data row {i + 1} is incorrect.'
        for j, (actual_val, expected_val) in enumerate(zip(actual_row, expected_row)):
            assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
                f'Mismatch at row {i + 1}, col {j}: expected {expected_val:.4f}, got {actual_val:.4f}'


def test_cov_matrix_txt():
    output_path = '/home/user/cov_matrix.txt'
    assert os.path.exists(output_path), f'{output_path} is missing.'
    _, expected_cov = compute_expected_data()

    with open(output_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == len(expected_cov), 'Number of rows in covariance matrix is incorrect.'
    for i, (line, expected_row) in enumerate(zip(lines, expected_cov)):
        actual_row = [float(x) for x in line.split()]
        assert len(actual_row) == len(expected_row), f'Number of columns in covariance matrix row {i} is incorrect.'
        for j, (actual_val, expected_val) in enumerate(zip(actual_row, expected_row)):
            assert math.isclose(actual_val, expected_val, abs_tol=1e-3), \
                f'Covariance mismatch at ({i}, {j}): expected {expected_val:.4f}, got {actual_val:.4f}'


def test_pipeline_on_unseen_input():
    input_path = '/home/user/sensor_data.csv'
    with open(input_path, 'rb') as f:
        original_input = f.read()

    source_binary = '/tmp/etl_source_check_bin'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', '-I/home/user', '/home/user/etl.cpp', '-o', source_binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f'etl.cpp failed to compile:\n{compile_result.stderr}'

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    rows = []
    for _ in range(13):
        rows.append([
            f'{18.0 + rng.random() * 7.0:.8f}',
            f'{98.0 + rng.random() * 7.0:.8f}',
            f'{40.0 + rng.random() * 12.0:.8f}'
        ])
    rows[1][2] = ''
    rows[3][1] = ' '
    rows[6][0] = 'NaN'
    rows[9][0] = f'{85.0 + rng.random() * 20.0:.8f}'
    rows[11][1] = f'{175.0 + rng.random() * 30.0:.8f}'

    def write_challenge():
        with open(input_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['temp', 'pressure', 'humidity'])
            writer.writerows(rows)

    try:
        write_challenge()
        expected_data, expected_cov = compute_expected_data()

        for executable in ['/home/user/etl_bin', source_binary]:
            write_challenge()
            for output in ['/home/user/processed_data.csv', '/home/user/cov_matrix.txt']:
                if os.path.exists(output):
                    os.remove(output)
            result = subprocess.run([executable], cwd='/home/user', stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True, timeout=15)
            assert result.returncode == 0, f'{executable} failed on unseen input: {result.stderr}'
            assert_outputs(expected_data, expected_cov)
    finally:
        with open(input_path, 'wb') as f:
            f.write(original_input)
TEST_EOF

rm -f /home/user/processed_data.csv /home/user/cov_matrix.txt
run_ok=0
if [ -f /home/user/etl.cpp ] && [ -f /home/user/etl_bin ] && [ -x /home/user/etl_bin ]; then
    if (cd /home/user && timeout 15s /home/user/etl_bin); then
        run_ok=1
    fi
fi

if [ "$run_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
