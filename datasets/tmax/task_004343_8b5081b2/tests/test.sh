#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from collections import defaultdict

import pytest

SCRIPT_FILE = '/home/user/process_configs.py'
OUTPUT_FILE = '/home/user/output/final_stats.csv'
RAW_DATA_DIR = '/home/user/raw_data'
EXPECTED_HEADERS = ['event_id', 'timestamp', 'server_id', 'service_name', 'diff_line_count', 'rolling_avg_diff']


def get_expected_data():
    raw_rows = []
    for filename in os.listdir(RAW_DATA_DIR):
        if filename.endswith('.csv'):
            filepath = os.path.join(RAW_DATA_DIR, filename)
            with open(filepath, 'r', newline='') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    config_diff = row['config_diff']
                    diff_line_count = len(config_diff.split('\n')) if config_diff else 0
                    raw_rows.append({
                        'event_id': row['event_id'],
                        'timestamp': row['timestamp'],
                        'server_id': row['server_id'],
                        'service_name': row['service_name'],
                        'diff_line_count': diff_line_count
                    })

    raw_rows.sort(key=lambda x: (x['timestamp'], x['event_id']))
    service_history = defaultdict(list)
    expected_rows = []

    for row in raw_rows:
        history = service_history[row['service_name']]
        history.append(row['diff_line_count'])
        if len(history) > 3:
            history.pop(0)
        row['rolling_avg_diff'] = f"{sum(history) / len(history):.2f}"
        expected_rows.append(row)

    return expected_rows


def read_output():
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found at {OUTPUT_FILE}"
    with open(OUTPUT_FILE, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == EXPECTED_HEADERS, \
            f"Expected headers {EXPECTED_HEADERS}, got {reader.fieldnames}"
        return list(reader)


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_FILE],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"process_configs.py failed with status {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


@pytest.fixture(scope='module', autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_FILE), f"Required script not found at {SCRIPT_FILE}"
    assert not os.path.islink(SCRIPT_FILE), f"{SCRIPT_FILE} must be a real Python source file"
    assert stat.S_ISREG(os.stat(SCRIPT_FILE).st_mode), f"{SCRIPT_FILE} is not a regular file"
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    run_script()


@pytest.fixture(scope='module')
def expected_data(execute_submission):
    return get_expected_data()


@pytest.fixture(scope='module')
def actual_data(execute_submission):
    return read_output()


def test_script_implements_parallel_processing_and_validation():
    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_FILE)

    module_aliases = set()
    factory_aliases = set()
    allowed_factories = {'Pool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'multiprocessing' or item.name.startswith('multiprocessing.') or item.name == 'concurrent.futures':
                    module_aliases.add(item.asname or item.name.split('.')[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == 'multiprocessing' or node.module.startswith('multiprocessing.') or node.module == 'concurrent.futures'):
                for item in node.names:
                    if item.name in allowed_factories:
                        factory_aliases.add(item.asname or item.name)

    def root_name(expr):
        while isinstance(expr, ast.Attribute):
            expr = expr.value
        return expr.id if isinstance(expr, ast.Name) else None

    parallel_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in factory_aliases:
            parallel_calls.append(node)
        elif isinstance(node.func, ast.Attribute):
            if node.func.attr in allowed_factories and root_name(node.func) in module_aliases:
                parallel_calls.append(node)

    assert parallel_calls, \
        'The script must actually construct a multiprocessing or concurrent.futures worker/executor'

    functions = [node for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
    validation_functions = []
    for fn in functions:
        body_text = ast.get_source_segment(source, fn) or ast.unparse(fn)
        lower_name = fn.name.lower()
        if 'valid' in lower_name or ('diff_line_count' in body_text and 'rolling_avg_diff' in body_text):
            validation_functions.append(fn)

    assert validation_functions, 'A validation function for the calculated columns must be implemented'
    validation_names = {fn.name for fn in validation_functions}
    validation_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Name) and node.func.id in validation_names)
             or (isinstance(node.func, ast.Attribute) and node.func.attr in validation_names))
    ]
    assert validation_calls, 'The validation function must be called before output is saved'

    lower_source = source.lower()
    assert any(token in lower_source for token in ('isna(', 'isnull(', 'notna(', 'notnull(')), \
        'Validation must check for null/NaN calculated values'
    assert ('diff_line_count' in source and 'rolling_avg_diff' in source), \
        'Validation must cover diff_line_count and rolling_avg_diff'

    has_zero_comparison = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Compare):
            values = [node.left] + list(node.comparators)
            if any(isinstance(value, ast.Constant) and value.value == 0 for value in values):
                if any(isinstance(op, (ast.Lt, ast.LtE, ast.Gt, ast.GtE)) for op in node.ops):
                    has_zero_comparison = True
    has_zero_comparison = has_zero_comparison or any(token in lower_source for token in ('.ge(0', '.gt(0', '.le(0', '.lt(0'))
    assert has_zero_comparison, 'Validation must enforce the non-negative rolling average rule'

    save_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'to_csv'
    ]
    assert save_calls, 'The script must save the result as a CSV'
    assert min(call.lineno for call in validation_calls) < max(call.lineno for call in save_calls), \
        'The validation function must be called before saving the CSV'


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found at {OUTPUT_FILE}"


def test_no_missing_values_and_non_negative(actual_data):
    for i, row in enumerate(actual_data):
        for key, val in row.items():
            assert val is not None and val.strip() != '', f"Missing value in row {i+1} for column {key}"
        rolling_avg = float(row['rolling_avg_diff'])
        assert rolling_avg >= 0, f"rolling_avg_diff must be >= 0, got {rolling_avg} in row {i+1}"


def test_sorting(actual_data, expected_data):
    actual_events = [row['event_id'] for row in actual_data]
    expected_events = [row['event_id'] for row in expected_data]
    assert actual_events == expected_events, \
        f"Output is not sorted correctly. Expected order: {expected_events}, Actual: {actual_events}"


def test_source_metadata_is_preserved(actual_data, expected_data):
    assert len(actual_data) == len(expected_data)
    for actual, expected in zip(actual_data, expected_data):
        for column in ('event_id', 'timestamp', 'server_id', 'service_name'):
            assert actual[column] == expected[column], \
                f"Incorrect {column} for event {expected['event_id']}: expected {expected[column]!r}, got {actual[column]!r}"


def test_diff_line_count_and_rolling_avg(actual_data, expected_data):
    actual_dict = {row['event_id']: row for row in actual_data}
    for expected_row in expected_data:
        event_id = expected_row['event_id']
        assert event_id in actual_dict, f"Missing event_id {event_id} in output"
        actual_row = actual_dict[event_id]
        assert int(actual_row['diff_line_count']) == expected_row['diff_line_count'], \
            f"Incorrect diff_line_count for event {event_id}. Expected {expected_row['diff_line_count']}, got {actual_row['diff_line_count']}"
        expected_avg = float(expected_row['rolling_avg_diff'])
        actual_avg = float(actual_row['rolling_avg_diff'])
        assert math.isclose(actual_avg, expected_avg, abs_tol=0.01), \
            f"Incorrect rolling_avg_diff for event {event_id}. Expected {expected_avg}, got {actual_avg}"


def test_script_processes_fresh_multiline_inputs():
    token = secrets.token_hex(6)
    parent = tempfile.mkdtemp(prefix='config-verifier-', dir='/tmp')
    backup = os.path.join(parent, 'raw_data_backup')
    os.rename(RAW_DATA_DIR, backup)
    os.makedirs(RAW_DATA_DIR)

    challenge = [
        [f'{token}-03', '2041-07-01T09:04:00Z', f'srv-{token}-c', f'api-{token}', 'a\nb\nc'],
        [f'{token}-01', '2041-07-01T09:00:00Z', f'srv-{token}-a', f'api-{token}', 'single'],
        [f'{token}-04', '2041-07-01T09:04:00Z', f'srv-{token}-d', f'cache-{token}', 'x\ny'],
        [f'{token}-02', '2041-07-01T09:02:00Z', f'srv-{token}-b', f'api-{token}', ''],
        [f'{token}-05', '2041-07-01T09:06:00Z', f'srv-{token}-e', f'api-{token}', 'q\nr\ns\nt'],
    ]

    try:
        for filename, rows in (('part_one.csv', challenge[:2]), ('part_two.csv', challenge[2:])):
            with open(os.path.join(RAW_DATA_DIR, filename), 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['event_id', 'timestamp', 'server_id', 'service_name', 'config_diff'])
                writer.writerows(rows)

        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        run_script()
        expected = get_expected_data()
        actual = read_output()
        assert len(actual) == len(expected)
        for got, wanted in zip(actual, expected):
            for column in ('event_id', 'timestamp', 'server_id', 'service_name'):
                assert got[column] == wanted[column]
            assert int(got['diff_line_count']) == wanted['diff_line_count']
            assert math.isclose(float(got['rolling_avg_diff']), float(wanted['rolling_avg_diff']), abs_tol=0.01)
    finally:
        shutil.rmtree(RAW_DATA_DIR, ignore_errors=True)
        os.rename(backup, RAW_DATA_DIR)
        shutil.rmtree(parent, ignore_errors=True)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
