#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import stat
import subprocess
import uuid
from datetime import datetime
from pathlib import Path

import pytest

RAW = Path('/home/user/raw_data.csv')
SCRIPT = Path('/home/user/process.py')
CLEANED = Path('/home/user/cleaned_data.csv')
REPORT = Path('/home/user/report.md')

CANONICAL_RAW = '''timestamp,temp_A,log_A,temp_B,log_B
2023-11-01 10:00:00,20.5,Valve opened.,22.1,System normal
2023-11-01 10:05:00,21.0,,22.5,
2023-11-01 10:30:00,23.5,Valve opened heavily!,23.0,Warning: High pressure
2023-11-01 11:00:00,21.0,System cool down.,21.5,Warning - high pressures!
'''


def check_script_uses_jinja2():
    assert SCRIPT.exists(), 'process.py script is missing'
    assert SCRIPT.is_file() and not SCRIPT.is_symlink(), 'process.py must be a regular file'
    source = SCRIPT.read_text(encoding='utf-8')
    tree = ast.parse(source, filename=str(SCRIPT))
    imported = any(
        (isinstance(node, ast.Import) and any(a.name == 'jinja2' or a.name.startswith('jinja2.') for a in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == 'jinja2' or node.module.startswith('jinja2.')))
        for node in ast.walk(tree)
    )
    renders = any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'render'
        for node in ast.walk(tree)
    )
    assert imported, 'process.py must import and use Jinja2 for report generation'
    assert renders, 'process.py must render the report through a Jinja2 template'


def run_pipeline(raw_text):
    RAW.write_text(raw_text, encoding='utf-8')
    for output in (CLEANED, REPORT):
        if output.exists() or output.is_symlink():
            output.unlink()
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f'process.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert CLEANED.exists(), 'cleaned_data.csv is missing after process.py ran'
    assert REPORT.exists(), 'report.md is missing after process.py ran'
    assert CLEANED.is_file() and not CLEANED.is_symlink(), 'cleaned_data.csv must be a regular file'
    assert REPORT.is_file() and not REPORT.is_symlink(), 'report.md must be a regular file'


def read_rows():
    with CLEANED.open('r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        headers = reader.fieldnames
    return headers, rows


def normalized(text):
    cleaned = ''.join(ch.lower() if (ch.isalnum() or ch == ' ') else '' for ch in text)
    return [word for word in cleaned.split(' ') if word]


def parse_tokens(value):
    try:
        parsed = ast.literal_eval(value)
    except Exception as exc:
        raise AssertionError(f'normalized_log is not a serialized token list: {value!r}') from exc
    assert isinstance(parsed, list), f'normalized_log must contain a list, got {parsed!r}'
    assert all(isinstance(token, str) for token in parsed), 'normalized_log tokens must be strings'
    return parsed


def test_complete_pipeline_on_original_and_unseen_input():
    check_script_uses_jinja2()

    # First execute the submitted artifact on the original input and retain all
    # assertions made by the original verifier.
    run_pipeline(CANONICAL_RAW)

    assert os.path.exists('/home/user/process.py'), 'process.py script is missing'
    assert os.path.exists('/home/user/cleaned_data.csv'), 'cleaned_data.csv is missing'
    assert os.path.exists('/home/user/report.md'), 'report.md is missing'

    report = REPORT.read_text(encoding='utf-8')
    assert 'Average Temperature for Sensor A:' in report, 'Missing Average Temperature for Sensor A in report'
    assert 'Average Temperature for Sensor B:' in report, 'Missing Average Temperature for Sensor B in report'
    assert '21.85' in report, 'Incorrect Average Temperature for Sensor A (expected ~21.85)'
    assert '22.31' in report, 'Incorrect Average Temperature for Sensor B (expected ~22.31)'
    pair_match_1 = '"Valve opened." and "Valve opened heavily!"' in report
    pair_match_2 = '"Valve opened heavily!" and "Valve opened."' in report
    assert pair_match_1 or pair_match_2, 'Missing the expected similar log pair in the report'
    assert '0.67' in report or '0.66' in report, 'Missing or incorrect similarity score for the log pair (expected ~0.67)'

    headers, rows = read_rows()
    assert len(rows) > 0, 'cleaned_data.csv is empty'
    assert headers is not None, 'cleaned_data.csv has no headers'
    required_columns = {'timestamp', 'sensor', 'temp', 'log'}
    assert required_columns.issubset(set(headers)), f'cleaned_data.csv is missing required columns. Found: {headers}'
    sensors = {row['sensor'] for row in rows if 'sensor' in row}
    assert 'A' in sensors, 'Sensor A data missing in cleaned_data.csv'
    assert 'B' in sensors, 'Sensor B data missing in cleaned_data.csv'

    # Now use an unseen input. Its irregular 08:10 values are needed to
    # interpolate the 08:15 grid point, while its logs exercise normalization,
    # distinct-pair Jaccard calculation, alphabetical ordering, and formatting.
    nonce = uuid.uuid4().hex[:10]
    aword = f'Pump{nonce}'
    bword = f'North{nonce}'
    a_log_1 = f'{aword.capitalize()}, alpha fault!'
    a_log_2 = f'{aword.capitalize()} alpha severe fault'
    b_log_1 = f'{bword.capitalize()} fan ready.'
    b_log_2 = f'{bword.capitalize()} fan fully ready'

    a0, a10, a30, a60 = 11.0, 23.0, 47.0, 71.0
    b0, b10, b30, b60 = 34.0, 42.0, 58.0, 18.0
    challenge = f'''timestamp,temp_A,log_A,temp_B,log_B
2024-02-03 08:00:00,{a0},{a_log_1},{b0},{b_log_1}
2024-02-03 08:10:00,{a10},off-grid {nonce},{b10},off-grid other {nonce}
2024-02-03 08:30:00,{a30},{a_log_2},{b30},{b_log_2}
2024-02-03 09:00:00,{a60},isolated event {nonce},{b60},totally different {nonce}
'''
    run_pipeline(challenge)

    headers, rows = read_rows()
    assert headers is not None
    assert {'timestamp', 'sensor', 'temp', 'log', 'normalized_log'}.issubset(set(headers)), \
        f'cleaned_data.csv lacks required output columns: {headers}'
    assert len(rows) == 10, f'expected five 15-minute rows per sensor, found {len(rows)} rows'

    expected_times = [
        datetime(2024, 2, 3, 8, 0), datetime(2024, 2, 3, 8, 15),
        datetime(2024, 2, 3, 8, 30), datetime(2024, 2, 3, 8, 45),
        datetime(2024, 2, 3, 9, 0),
    ]
    a15 = a10 + (a30 - a10) * (5.0 / 20.0)
    b15 = b10 + (b30 - b10) * (5.0 / 20.0)
    expected_temps = {
        'A': [a0, a15, a30, (a30 + a60) / 2.0, a60],
        'B': [b0, b15, b30, (b30 + b60) / 2.0, b60],
    }
    expected_logs = {
        'A': [a_log_1, '', a_log_2, '', f'isolated event {nonce}'],
        'B': [b_log_1, '', b_log_2, '', f'totally different {nonce}'],
    }

    actual = {}
    for row in rows:
        assert row['sensor'] in {'A', 'B'}, f'unexpected sensor value: {row["sensor"]!r}'
        try:
            timestamp = datetime.fromisoformat(row['timestamp'])
        except ValueError as exc:
            raise AssertionError(f'invalid timestamp in cleaned CSV: {row["timestamp"]!r}') from exc
        key = (row['sensor'], timestamp)
        assert key not in actual, f'duplicate output row for {key}'
        actual[key] = row

    for sensor in ('A', 'B'):
        for index, timestamp in enumerate(expected_times):
            key = (sensor, timestamp)
            assert key in actual, f'missing strict 15-minute row {key}'
            row = actual[key]
            assert float(row['temp']) == pytest.approx(expected_temps[sensor][index], abs=1e-8), \
                f'incorrect interpolation for {key}'
            expected_log = expected_logs[sensor][index]
            assert row['log'] == expected_log, f'incorrect gap-filled log for {key}'
            assert parse_tokens(row['normalized_log']) == normalized(expected_log), \
                f'incorrect normalized_log for {key}'

    avg_a = sum(expected_temps['A']) / 5.0
    avg_b = sum(expected_temps['B']) / 5.0
    pairs = []
    for left, right in ((a_log_1, a_log_2), (b_log_1, b_log_2)):
        first, second = sorted((left, right))
        pairs.append((first, second, 0.75))
    pairs.sort(key=lambda item: item[0])
    pair_lines = '\n'.join(
        f'- "{first}" and "{second}" (Similarity: {score:.2f})'
        for first, second, score in pairs
    )
    expected_report = f'''# Data Processing Report

## Missing Value Imputation
Average Temperature for Sensor A: {avg_a:.2f}
Average Temperature for Sensor B: {avg_b:.2f}

## Similar Log Pairs
{pair_lines}'''
    actual_report = REPORT.read_text(encoding='utf-8').strip()
    assert actual_report == expected_report, \
        f'report does not match computed pipeline results.\nExpected:\n{expected_report}\nActual:\n{actual_report}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
