#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ALPHA_PATH = '/home/user/sensor_alpha.csv'
BETA_PATH = '/home/user/sensor_beta.csv'
PARQUET_PATH = '/home/user/processed_data.parquet'
SUMMARY_PATH = '/home/user/summary.txt'
REQUIRED_COLUMNS = ['id', 'timestamp', 'magnitude', 'temp_norm', 'pressure']


def load_and_validate_sources():
    # Reconstruct the setup data so modifying the input files cannot change the oracle.
    np.random.seed(42)
    n_rows = 50000
    ids = np.arange(1, n_rows + 1)
    timestamps = pd.date_range(start='2023-01-01', periods=n_rows, freq='s')

    pristine_alpha = pd.DataFrame({
        'id': ids,
        'timestamp': timestamps,
        'x_coord': np.random.uniform(-100, 100, n_rows),
        'y_coord': np.random.uniform(-100, 100, n_rows),
        'z_coord': np.random.uniform(-100, 100, n_rows),
    }).sample(frac=1).reset_index(drop=True)

    pristine_beta = pd.DataFrame({
        'id': ids,
        'timestamp': timestamps,
        'temperature': np.random.uniform(20, 100, n_rows),
        'pressure': np.random.uniform(900, 1100, n_rows),
    }).sample(frac=1).reset_index(drop=True)

    alpha = pd.read_csv(ALPHA_PATH, parse_dates=['timestamp'])
    beta = pd.read_csv(BETA_PATH, parse_dates=['timestamp'])

    pd.testing.assert_frame_equal(
        alpha, pristine_alpha, check_dtype=False, check_exact=False,
        rtol=1e-12, atol=1e-12,
        obj='sensor_alpha.csv was modified',
    )
    pd.testing.assert_frame_equal(
        beta, pristine_beta, check_dtype=False, check_exact=False,
        rtol=1e-12, atol=1e-12,
        obj='sensor_beta.csv was modified',
    )
    return alpha, beta


def expected_result():
    alpha, beta = load_and_validate_sources()
    expected = alpha.merge(beta, on=['id', 'timestamp'], how='inner')
    expected['magnitude'] = np.sqrt(
        expected['x_coord'] ** 2
        + expected['y_coord'] ** 2
        + expected['z_coord'] ** 2
    )
    expected['temp_norm'] = np.log(expected['temperature'])
    return expected[REQUIRED_COLUMNS]


def test_parquet_file_exists_and_valid():
    """Test that the processed Parquet file exists and has valid Parquet magic bytes."""
    assert os.path.exists(PARQUET_PATH), f"Missing processed file: {PARQUET_PATH}"
    assert os.path.isfile(PARQUET_PATH), f"Expected a file: {PARQUET_PATH}"
    assert os.path.getsize(PARQUET_PATH) > 0, f"File is empty: {PARQUET_PATH}"

    with open(PARQUET_PATH, 'rb') as f:
        data = f.read()

    assert data.startswith(b'PAR1'), "File does not start with Parquet magic bytes 'PAR1'."
    assert data.endswith(b'PAR1'), "File does not end with Parquet magic bytes 'PAR1'."

    # A real Parquet parser must be able to read the file and its metadata.
    parquet_file = pq.ParquetFile(PARQUET_PATH)
    assert parquet_file.metadata.num_rows == 50000
    assert parquet_file.metadata.num_row_groups > 0


def test_parquet_columns_present():
    """Test that the required columns are present in the Parquet file metadata."""
    with open(PARQUET_PATH, 'rb') as f:
        data = f.read()

    expected_columns = [b'id', b'timestamp', b'magnitude', b'temp_norm', b'pressure']
    for col in expected_columns:
        assert col in data, f"Column {col.decode()} not found in Parquet file metadata."

    parquet_file = pq.ParquetFile(PARQUET_PATH)
    assert parquet_file.schema_arrow.names == REQUIRED_COLUMNS, (
        f"Expected exactly these columns in order: {REQUIRED_COLUMNS}; "
        f"got {parquet_file.schema_arrow.names}"
    )

    # Verify that every physical column chunk is Snappy-compressed.
    for row_group_index in range(parquet_file.metadata.num_row_groups):
        row_group = parquet_file.metadata.row_group(row_group_index)
        for column_index in range(row_group.num_columns):
            column = row_group.column(column_index)
            assert column.compression.upper() == 'SNAPPY', (
                f"Column {column.path_in_schema} in row group {row_group_index} "
                f"uses {column.compression}, not Snappy"
            )


def test_parquet_rows_match_join_and_engineered_features():
    expected = expected_result()
    actual = pq.read_table(PARQUET_PATH).to_pandas()

    assert list(actual.columns) == REQUIRED_COLUMNS
    assert len(actual) == len(expected)

    actual = actual.copy()
    actual['timestamp'] = pd.to_datetime(actual['timestamp'], errors='raise')
    actual = actual.sort_values(['id', 'timestamp']).reset_index(drop=True)
    expected = expected.sort_values(['id', 'timestamp']).reset_index(drop=True)

    pd.testing.assert_frame_equal(
        actual,
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-10,
        atol=1e-10,
    )


def test_summary_file_contents():
    """Test that the summary.txt file exists and contains the correct mean values."""
    assert os.path.exists(SUMMARY_PATH), f"Missing summary file: {SUMMARY_PATH}"
    assert os.path.isfile(SUMMARY_PATH), f"Expected a file: {SUMMARY_PATH}"

    with open(SUMMARY_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    # Normalize line endings.
    content = content.replace('\r\n', '\n')

    # Preserve the original known-value assertion.
    expected_content = "Mean Magnitude: 99.8291\nMean Temp Norm: 4.0264"
    assert content == expected_content, (
        f"Summary file contents do not match expected values.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )

    # Also derive the expected report from the source join and engineered features.
    expected = expected_result()
    derived_content = (
        f"Mean Magnitude: {expected['magnitude'].mean():.4f}\n"
        f"Mean Temp Norm: {expected['temp_norm'].mean():.4f}"
    )
    assert content == derived_content, (
        f"Summary does not match the recomputed data.\n"
        f"Expected:\n{derived_content}\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
