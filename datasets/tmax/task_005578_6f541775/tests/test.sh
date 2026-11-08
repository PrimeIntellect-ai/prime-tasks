#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import re
import pytest
import pandas as pd
import pyarrow.parquet as pq
from scipy import stats
from pandas.testing import assert_frame_equal


def get_token_count(text):
    text = text.lower()
    # Remove all non-alphanumeric characters (excluding spaces)
    text = re.sub(r'[^a-z0-9\s]', '', text)
    # Split by spaces and remove empty strings
    tokens = [t for t in text.split(' ') if t]
    return len(tokens)


def compute_pearson(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den = (sum((xi - mean_x)**2 for xi in x) * sum((yi - mean_y)**2 for yi in y))**0.5
    return num / den


def compute_welchs_t_test(x, y):
    nx = len(x)
    ny = len(y)
    mean_x = sum(x) / nx
    mean_y = sum(y) / ny
    var_x = sum((xi - mean_x)**2 for xi in x) / (nx - 1)
    var_y = sum((yi - mean_y)**2 for yi in y) / (ny - 1)

    t_stat = (mean_x - mean_y) / math.sqrt(var_x / nx + var_y / ny)
    return t_stat


@pytest.fixture(scope="module")
def expected_data():
    csv_path = '/home/user/customer_data.csv'
    assert os.path.exists(csv_path), "Original CSV missing."

    source = pd.read_csv(csv_path)
    expected = source.copy()
    expected['token_count'] = expected['feedback_text'].fillna('').map(get_token_count)
    return expected


@pytest.fixture(scope="module")
def expected_stats():
    csv_path = '/home/user/customer_data.csv'
    assert os.path.exists(csv_path), "Original CSV missing."

    token_counts = []
    interaction_times = []
    premium_tokens = []
    non_premium_tokens = []

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            tc = get_token_count(row['feedback_text'])
            it = float(row['interaction_time'])
            is_prem = int(row['is_premium'])

            token_counts.append(tc)
            interaction_times.append(it)
            if is_prem == 1:
                premium_tokens.append(tc)
            else:
                non_premium_tokens.append(tc)

    corr = compute_pearson(token_counts, interaction_times)
    t_stat = compute_welchs_t_test(premium_tokens, non_premium_tokens)
    scipy_result = stats.ttest_ind(premium_tokens, non_premium_tokens, equal_var=False)

    return {
        'correlation': corr,
        't_stat': t_stat,
        'p_value': float(scipy_result.pvalue)
    }


def test_parquet_file_created():
    parquet_path = '/home/user/processed_data.parquet'
    assert os.path.exists(parquet_path), f"Parquet file missing at {parquet_path}"
    assert os.path.isfile(parquet_path), f"Path {parquet_path} is not a file"

    # Check for Parquet magic bytes 'PAR1'
    with open(parquet_path, 'rb') as f:
        magic = f.read(4)
        assert magic == b'PAR1', "File does not appear to be a valid Parquet file (missing PAR1 magic bytes)"


def test_parquet_contents_and_compression(expected_data):
    parquet_path = '/home/user/processed_data.parquet'

    try:
        parquet_file = pq.ParquetFile(parquet_path)
        actual = pd.read_parquet(parquet_path)
    except Exception as exc:
        pytest.fail(f"processed_data.parquet is not a readable Parquet file: {exc}")

    expected_columns = [
        'user_id', 'feedback_text', 'interaction_time', 'is_premium', 'token_count'
    ]
    assert list(actual.columns) == expected_columns, \
        f"Expected columns {expected_columns}, got {list(actual.columns)}"
    assert len(actual) == len(expected_data), \
        f"Expected {len(expected_data)} rows, got {len(actual)}"

    assert_frame_equal(
        actual.reset_index(drop=True),
        expected_data.reset_index(drop=True),
        check_dtype=True,
        check_exact=True,
        obj='processed dataframe'
    )

    metadata = parquet_file.metadata
    assert metadata.num_rows == len(expected_data), "Parquet metadata has the wrong row count"
    assert metadata.num_row_groups > 0, "Parquet file contains no row groups"
    for row_group_index in range(metadata.num_row_groups):
        row_group = metadata.row_group(row_group_index)
        for column_index in range(row_group.num_columns):
            column = row_group.column(column_index)
            assert column.compression == 'SNAPPY', \
                f"Column {column.path_in_schema} is compressed with {column.compression}, not SNAPPY"


def test_stats_report_json(expected_stats):
    json_path = '/home/user/stats_report.json'
    assert os.path.exists(json_path), f"JSON report missing at {json_path}"

    with open(json_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("stats_report.json is not a valid JSON file.")

    assert 'correlation' in report, "Missing 'correlation' in JSON report"
    assert 't_stat' in report, "Missing 't_stat' in JSON report"
    assert 'p_value' in report, "Missing 'p_value' in JSON report"

    assert abs(report['correlation'] - expected_stats['correlation']) < 0.001, \
        f"Expected correlation ~{expected_stats['correlation']:.4f}, got {report['correlation']}"

    assert abs(report['t_stat'] - expected_stats['t_stat']) < 0.001, \
        f"Expected t_stat ~{expected_stats['t_stat']:.4f}, got {report['t_stat']}"

    # p_value should be extremely close to 0 given the large sample size and effect size
    assert report['p_value'] >= 0, "p_value cannot be negative"
    assert report['p_value'] < 0.01, f"Expected p_value to be very small, got {report['p_value']}"

    assert set(report.keys()) == {'correlation', 't_stat', 'p_value'}, \
        f"JSON report must contain exactly correlation, t_stat, and p_value; got {set(report.keys())}"
    for key in ('correlation', 't_stat', 'p_value'):
        assert isinstance(report[key], (int, float)) and not isinstance(report[key], bool), \
            f"{key} must be a numeric JSON value"
        assert math.isfinite(report[key]), f"{key} must be finite"
        expected_rounded = round(expected_stats[key], 4)
        assert abs(report[key] - expected_rounded) < 1e-12, \
            f"Expected {key} rounded to 4 decimal places to be {expected_rounded}, got {report[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
