#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
from collections import Counter

import pandas as pd
import pytest
from scipy.stats import ttest_ind


def get_stats(data):
    n = len(data)
    if n == 0:
        return 0, 0, 0
    mean = sum(data) / n
    if n == 1:
        return n, mean, 0
    var = sum((x - mean) ** 2 for x in data) / (n - 1)
    return n, mean, var


def expected_rows():
    tickets = pd.read_csv('/home/user/tickets.csv')
    labels = pd.read_csv('/home/user/labels.csv')
    merged = tickets.merge(labels, on='ticket_id', how='left')
    merged = merged.dropna(subset=['label'])[['ticket_id', 'text', 'label']]
    return [
        {
            'ticket_id': str(int(row.ticket_id)),
            'text': str(row.text),
            'label': str(row.label),
        }
        for row in merged.itertuples(index=False)
    ]


def test_clean_data_csv():
    file_path = '/home/user/clean_data.csv'
    assert os.path.isfile(file_path), f'{file_path} does not exist.'

    with open(file_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['ticket_id', 'text', 'label'], \
            f'clean_data.csv must contain exactly ticket_id,text,label columns; found {reader.fieldnames}.'
        rows = list(reader)

    assert len(rows) == 383, f'Expected exactly 383 valid records in clean_data.csv, found {len(rows)}.'

    for i, row in enumerate(rows):
        tid = row.get('ticket_id', '')
        assert tid, f'Missing ticket_id at row {i+1}'
        assert '.' not in tid, f"ticket_id '{tid}' appears to be a float. It must be an integer."
        assert row.get('label') in ('bug', 'feature'), f"Unexpected label '{row.get('label')}' at row {i+1}."

    expected = expected_rows()
    actual_records = Counter((r['ticket_id'], r['text'], r['label']) for r in rows)
    expected_records = Counter((r['ticket_id'], r['text'], r['label']) for r in expected)
    assert actual_records == expected_records, \
        'clean_data.csv does not exactly match the labeled rows from the required left join.'


def test_results_json():
    json_path = '/home/user/results.json'
    csv_path = '/home/user/clean_data.csv'

    assert os.path.isfile(json_path), f'{json_path} does not exist.'

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{json_path} is not valid JSON.')

    required_keys = {
        'num_valid_records',
        'mean_tokens_bug',
        'mean_tokens_feature',
        't_statistic',
        'p_value'
    }
    assert required_keys.issubset(results.keys()), f'Missing keys in results.json. Found: {list(results.keys())}'
    assert set(results.keys()) == required_keys, \
        f'results.json must contain exactly the specified keys. Found: {list(results.keys())}'

    with open(csv_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    bug_lengths = [len(r['text'].split()) for r in rows if r['label'] == 'bug']
    feature_lengths = [len(r['text'].split()) for r in rows if r['label'] == 'feature']

    n1, m1, v1 = get_stats(bug_lengths)
    n2, m2, v2 = get_stats(feature_lengths)
    expected_t = (m1 - m2) / math.sqrt(v1/n1 + v2/n2)

    assert results['num_valid_records'] == len(rows), \
        f"num_valid_records should be {len(rows)}, got {results['num_valid_records']}."
    assert math.isclose(results['mean_tokens_bug'], round(m1, 2), abs_tol=0.01), \
        f"mean_tokens_bug mismatch. Expected ~{round(m1, 2)}, got {results['mean_tokens_bug']}."
    assert math.isclose(results['mean_tokens_feature'], round(m2, 2), abs_tol=0.01), \
        f"mean_tokens_feature mismatch. Expected ~{round(m2, 2)}, got {results['mean_tokens_feature']}."
    assert math.isclose(abs(results['t_statistic']), abs(round(expected_t, 2)), abs_tol=0.02), \
        f"t_statistic mismatch. Expected ~{round(expected_t, 2)}, got {results['t_statistic']}."
    assert isinstance(results['p_value'], (int, float)), 'p_value must be a number.'
    assert 0 <= results['p_value'] <= 1, 'p_value must be between 0 and 1.'

    source_rows = expected_rows()
    source_bug_lengths = [len(r['text'].split()) for r in source_rows if r['label'] == 'bug']
    source_feature_lengths = [len(r['text'].split()) for r in source_rows if r['label'] == 'feature']
    source_test = ttest_ind(source_bug_lengths, source_feature_lengths, equal_var=False)

    assert results['num_valid_records'] == len(source_rows), \
        'num_valid_records does not match the required source join.'
    assert math.isclose(results['mean_tokens_bug'], round(sum(source_bug_lengths) / len(source_bug_lengths), 2), abs_tol=1e-9), \
        'mean_tokens_bug does not match the source data.'
    assert math.isclose(results['mean_tokens_feature'], round(sum(source_feature_lengths) / len(source_feature_lengths), 2), abs_tol=1e-9), \
        'mean_tokens_feature does not match the source data.'
    assert math.isclose(results['t_statistic'], round(float(source_test.statistic), 2), abs_tol=1e-9), \
        't_statistic does not match the signed Welch t-statistic.'
    assert math.isclose(results['p_value'], round(float(source_test.pvalue), 4), abs_tol=1e-9), \
        'p_value does not match the Welch t-test result.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
