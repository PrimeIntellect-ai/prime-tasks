#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/home/user/.cargo/bin:/root/.cargo/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import subprocess

import pytest

PROJECT_DIR = '/home/user/ml_pipeline'
TRAIN_FILE = '/home/user/train_processed.csv'
TEST_FILE = '/home/user/test_processed.csv'
RAW_FILE = '/home/user/raw_data.csv'
EXPECTED_HEADER = ['id', 'feature_x', 'label']


def read_strict_csv(path):
    with open(path, 'r', newline='') as f:
        rows = list(csv.reader(f))
    assert rows, f'{path} is empty'
    assert rows[0] == EXPECTED_HEADER, f'Header is incorrect in {path}: {rows[0]}'
    for line_number, row in enumerate(rows[1:], start=2):
        assert len(row) == 3, f'{path} line {line_number} does not have exactly 3 columns: {row}'
    return rows[1:]


def canonical_raw_rows():
    rows = []
    for i in range(1, 81):
        rows.append([str(i), '' if i % 8 == 0 else '10.0', '0' if i % 8 == 0 else '1'])
    for i in range(81, 101):
        rows.append([str(i), '' if i % 4 == 0 else '50.0', '0' if i % 4 == 0 else '1'])
    return rows


def expected_processed_rows():
    raw_rows = read_strict_csv(RAW_FILE)
    assert raw_rows == canonical_raw_rows(), 'raw_data.csv was modified from the supplied dataset'
    assert len(raw_rows) == 100

    train_raw = raw_rows[:80]
    test_raw = raw_rows[80:]
    observed_train_values = [float(row[1]) for row in train_raw if row[1] != '']
    assert observed_train_values, 'Training data has no non-missing feature_x values'
    train_mean = sum(observed_train_values) / len(observed_train_values)

    def process(rows):
        return [
            (row[0], train_mean if row[1] == '' else float(row[1]), row[2])
            for row in rows
        ]

    return process(train_raw), process(test_raw)


@pytest.fixture(scope='session', autouse=True)
def run_submitted_rust_program():
    cargo_toml = os.path.join(PROJECT_DIR, 'Cargo.toml')
    main_rs = os.path.join(PROJECT_DIR, 'src', 'main.rs')
    assert os.path.isdir(PROJECT_DIR), f'Rust project directory not found: {PROJECT_DIR}'
    assert os.path.isfile(cargo_toml), f'Cargo.toml not found: {cargo_toml}'
    assert os.path.isfile(main_rs), f'Rust entry point not found: {main_rs}'

    for output in (TRAIN_FILE, TEST_FILE):
        if os.path.lexists(output):
            os.unlink(output)

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['CARGO_HOME'] = '/home/user/.cargo'
    env['RUSTUP_HOME'] = '/home/user/.rustup'
    result = subprocess.run(
        ['/home/user/.cargo/bin/cargo', 'run', '--quiet'],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f'cargo run failed:\n{result.stdout}'
    assert os.path.isfile(TRAIN_FILE), 'Rust program did not generate train_processed.csv'
    assert os.path.isfile(TEST_FILE), 'Rust program did not generate test_processed.csv'


def test_rust_project_exists():
    project_dir = '/home/user/ml_pipeline'
    cargo_toml = os.path.join(project_dir, 'Cargo.toml')

    assert os.path.isdir(project_dir), f"Rust project directory not found: {project_dir}"
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found: {cargo_toml}"


def test_all_processed_rows_match_chronological_split_and_training_imputation():
    expected_train, expected_test = expected_processed_rows()
    actual_train = read_strict_csv(TRAIN_FILE)
    actual_test = read_strict_csv(TEST_FILE)

    assert len(actual_train) == 80, f'Expected 80 train rows, got {len(actual_train)}'
    assert len(actual_test) == 20, f'Expected 20 test rows, got {len(actual_test)}'

    for dataset_name, actual, expected in (
        ('train_processed.csv', actual_train, expected_train),
        ('test_processed.csv', actual_test, expected_test),
    ):
        for index, (actual_row, expected_row) in enumerate(zip(actual, expected), start=1):
            expected_id, expected_feature, expected_label = expected_row
            assert actual_row[0] == expected_id, (
                f'{dataset_name} row {index} has id {actual_row[0]!r}; expected {expected_id!r}'
            )
            assert actual_row[2] == expected_label, (
                f'{dataset_name} id {expected_id} has label {actual_row[2]!r}; '
                f'expected {expected_label!r}'
            )
            assert actual_row[1] != '', f'{dataset_name} id {expected_id} still has missing feature_x'
            try:
                actual_feature = float(actual_row[1])
            except ValueError:
                pytest.fail(f'{dataset_name} id {expected_id} has invalid feature_x {actual_row[1]!r}')
            assert math.isfinite(actual_feature), (
                f'{dataset_name} id {expected_id} has non-finite feature_x {actual_row[1]!r}'
            )
            assert math.isclose(actual_feature, expected_feature, rel_tol=1e-12, abs_tol=1e-12), (
                f'{dataset_name} id {expected_id} has feature_x {actual_feature}; '
                f'expected {expected_feature}'
            )


def test_train_processed_csv():
    train_file = '/home/user/train_processed.csv'
    assert os.path.isfile(train_file), f"Processed train file not found: {train_file}"

    with open(train_file, 'r', newline='') as f:
        reader = list(csv.DictReader(f))

        assert f.name.endswith('train_processed.csv')
        assert reader[0].keys() == {'id', 'feature_x', 'label'}, "Header is incorrect in train_processed.csv"
        assert len(reader) == 80, f"Expected 80 data rows in train_processed.csv, got {len(reader)}"

        row_8 = next((r for r in reader if r['id'] == '8'), None)
        assert row_8 is not None, "Row with id 8 missing in train_processed.csv"
        try:
            val_8 = float(row_8['feature_x'])
        except ValueError:
            assert False, f"feature_x for id 8 is not a valid float: {row_8['feature_x']}"
        assert math.isclose(val_8, 10.0), f"Data leak detected or incorrect imputation in train set. Expected 10.0, got {val_8}"

        row_1 = next((r for r in reader if r['id'] == '1'), None)
        assert row_1 is not None, "Row with id 1 missing in train_processed.csv"
        assert math.isclose(float(row_1['feature_x']), 10.0), "Original data was modified incorrectly"


def test_test_processed_csv():
    test_file = '/home/user/test_processed.csv'
    assert os.path.isfile(test_file), f"Processed test file not found: {test_file}"

    with open(test_file, 'r', newline='') as f:
        reader = list(csv.DictReader(f))

        assert reader[0].keys() == {'id', 'feature_x', 'label'}, "Header is incorrect in test_processed.csv"
        assert len(reader) == 20, f"Expected 20 data rows in test_processed.csv, got {len(reader)}"

        row_84 = next((r for r in reader if r['id'] == '84'), None)
        assert row_84 is not None, "Row with id 84 missing in test_processed.csv"
        try:
            val_84 = float(row_84['feature_x'])
        except ValueError:
            assert False, f"feature_x for id 84 is not a valid float: {row_84['feature_x']}"
        assert math.isclose(val_84, 10.0), f"Data leak detected or incorrect imputation in test set. Expected 10.0, got {val_84}"

        row_81 = next((r for r in reader if r['id'] == '81'), None)
        assert row_81 is not None, "Row with id 81 missing in test_processed.csv"
        assert math.isclose(float(row_81['feature_x']), 50.0), "Original data was modified incorrectly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
