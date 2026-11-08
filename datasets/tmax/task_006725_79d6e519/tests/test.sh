#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import sys
import urllib.parse
from collections import Counter

import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/process_logs.py"
INPUT_PATH = "/home/user/raw_logs.csv"
OUTPUT_PATH = "/home/user/sampled_logs.json"
EXPECTED_KEYS = {'region', 'ip_address', 'date', 'method', 'endpoint', 'status_code'}


def build_normalized_dataframe():
    df = pd.read_csv(INPUT_PATH)
    date_columns = ['2023-10-01', '2023-10-02', '2023-10-03']

    long_df = df.melt(
        id_vars=['region', 'ip_address'],
        value_vars=date_columns,
        var_name='date',
        value_name='raw_requests'
    )
    long_df = long_df[
        long_df['raw_requests'].notna()
        & long_df['raw_requests'].astype(str).str.strip().ne('')
    ].copy()

    long_df['raw_request'] = long_df['raw_requests'].str.split('|')
    long_df = long_df.explode('raw_request', ignore_index=True)
    decoded = long_df['raw_request'].map(urllib.parse.unquote)
    parsed = decoded.str.extract(r'^"([A-Z]+)\s+([^\s]+)\s+[^\"]+"\s+(\d+)\s*$')

    assert parsed.notna().all(axis=None), "Verifier could not parse a source request."
    long_df['method'] = parsed[0]
    long_df['endpoint'] = parsed[1].str.split('?', n=1).str[0].str.lower()
    long_df['status_code'] = parsed[2].astype(int)

    return long_df[
        ['region', 'ip_address', 'date', 'method', 'endpoint', 'status_code']
    ].copy()


def build_expected_sample(normalized):
    sorted_df = normalized.sort_values(
        by=['date', 'ip_address', 'method', 'endpoint'],
        ascending=True
    )
    sampled_groups = []
    for _, group in sorted_df.groupby(['region', 'status_code'], sort=True):
        sampled_groups.append(
            group.sample(n=min(2, len(group)), random_state=42)
        )
    if not sampled_groups:
        return sorted_df.copy()
    return pd.concat(sampled_groups)


def record_key(record):
    return (
        record['region'],
        record['ip_address'],
        record['date'],
        record['method'],
        record['endpoint'],
        record['status_code'],
    )


# Derive the oracle from the source data before executing the submitted script.
ALL_EXPECTED_RECORDS = build_normalized_dataframe().to_dict(orient='records')
EXPECTED_SAMPLE = build_expected_sample(build_normalized_dataframe()).to_dict(orient='records')


@pytest.fixture(scope='session', autouse=True)
def run_submitted_script():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Submitted script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_process_logs_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."


def test_sampled_logs_json_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_sampled_logs_json_format():
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "Output file is not valid JSON."

    assert isinstance(data, list), "JSON output should be a list of records."
    if len(data) > 0:
        assert set(data[0].keys()) == EXPECTED_KEYS, (
            f"Expected keys {EXPECTED_KEYS}, got {set(data[0].keys())}"
        )


def test_sampled_logs_content_and_sampling():
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Preserve the original validity and normalization assertions.
    for record in data:
        assert record in ALL_EXPECTED_RECORDS, (
            f"Record {record} is not a valid parsed and cleaned log entry. "
            "Check your decoding, parsing, and normalization."
        )
        assert '?' not in record['endpoint'], (
            f"Query parameters should be removed from endpoint: {record['endpoint']}"
        )
        assert record['endpoint'] == record['endpoint'].lower(), (
            f"Endpoint should be lowercased: {record['endpoint']}"
        )

    expected_groups = {}
    for item in ALL_EXPECTED_RECORDS:
        key = (item['region'], item['status_code'])
        expected_groups[key] = expected_groups.get(key, 0) + 1

    actual_groups = {}
    for item in data:
        key = (item['region'], item['status_code'])
        actual_groups[key] = actual_groups.get(key, 0) + 1

    for key, total_count in expected_groups.items():
        expected_sampled = min(2, total_count)
        actual_sampled = actual_groups.get(key, 0)
        assert actual_sampled == expected_sampled, (
            f"Group {key} should have {expected_sampled} samples, but got {actual_sampled}."
        )

    for key in actual_groups:
        assert key in expected_groups, f"Found unexpected group {key} in output."

    # Verify the exact rows selected by sorting and pandas sampling with seed 42.
    actual_counter = Counter(record_key(record) for record in data)
    expected_counter = Counter(record_key(record) for record in EXPECTED_SAMPLE)
    assert actual_counter == expected_counter, (
        "Output does not contain the exact deterministic stratified sample produced "
        "after sorting and sampling each group with random_state=42."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
