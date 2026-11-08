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
import sys
import uuid

import pytest

SCRIPT = '/home/user/clean_data.py'
INPUT_CSV = '/home/user/input.csv'
CLEANED_CSV = '/home/user/cleaned.csv'
DROPPED_LOG = '/home/user/dropped.log'
UNICODE_ESCAPE = re.compile(r'\\u([0-9a-fA-F]{4})')


def decode_text(text):
    return UNICODE_ESCAPE.sub(lambda match: chr(int(match.group(1), 16)), text)


def expected_from_input():
    cleaned = []
    dropped = []
    with open(INPUT_CSV, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'date', 'text']
        for row in reader:
            if len(row) != 3:
                dropped.append(row[0] if row and row[0] else 'UNKNOWN')
            else:
                cleaned.append([row[0], row[1], decode_text(row[2])])
    return cleaned, dropped


def read_outputs():
    assert os.path.isfile(CLEANED_CSV), f'{CLEANED_CSV} does not exist.'
    assert os.path.isfile(DROPPED_LOG), f'{DROPPED_LOG} does not exist.'
    with open(CLEANED_CSV, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))
    assert rows, 'cleaned.csv is empty.'
    assert rows[0] == ['id', 'date', 'text'], 'Header in cleaned.csv is incorrect.'
    with open(DROPPED_LOG, 'r', encoding='utf-8') as f:
        dropped = [line.strip() for line in f if line.strip()]
    return rows[1:], dropped


def run_script_and_compare():
    for path in (CLEANED_CSV, DROPPED_LOG):
        if os.path.lexists(path):
            os.remove(path)
    expected_rows, expected_dropped = expected_from_input()
    subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    actual_rows, actual_dropped = read_outputs()
    assert actual_rows == expected_rows, 'cleaned.csv does not exactly match the decoded valid input rows.'
    assert actual_dropped == expected_dropped, 'dropped.log does not match malformed input rows in input order.'


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist.'
    assert not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular Python source file, not a symlink.'
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f'{SCRIPT} is not a regular file.'

    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imported = set()
    imported_parallel_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imported.add(alias.name)
        elif isinstance(node, ast.ImportFrom):
            imported.add(node.module or '')
            if node.module in ('multiprocessing', 'concurrent.futures'):
                for alias in node.names:
                    if alias.name in ('Pool', 'Process', 'ProcessPoolExecutor'):
                        imported_parallel_names.add(alias.asname or alias.name)

    assert not any(name == 'pandas' or name.startswith('pandas.') for name in imported), 'pandas may not be used for the core processing.'
    assert any(name == 'multiprocessing' or name.startswith('multiprocessing.') or name in ('concurrent', 'concurrent.futures') for name in imported), 'The script must import multiprocessing or concurrent.futures.'

    parallel_call = False
    streaming_evidence = any(isinstance(node, (ast.For, ast.AsyncFor)) for node in ast.walk(tree))
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            called_name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            called_name = node.func.attr
        else:
            called_name = ''
        if called_name in ('Pool', 'Process', 'ProcessPoolExecutor') or called_name in imported_parallel_names:
            parallel_call = True
        if called_name == 'readline' or (called_name == 'read' and node.args):
            streaming_evidence = True

    assert parallel_call, 'The script must actually construct a process-based worker pool, executor, or process.'
    assert streaming_evidence, 'The script must contain iterative or chunked streaming input processing.'

    # Exercise the submitted program on an unpredictable extension so fixed output
    # files or scripts hardcoded only for the original row set cannot pass.
    with open(INPUT_CSV, 'rb') as f:
        original_input = f.read()
    token = uuid.uuid4().hex
    valid_id = str(20000 + int(token[:6], 16))
    bad_id = str(int(valid_id) + 1)
    try:
        with open(INPUT_CSV, 'a', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([valid_id, '2026-09-11', f'Probe {token}, caf\\u00e9 and snowman \\u2603'])
            f.write(f'{bad_id},2026-09-11\n')
        run_script_and_compare()
    finally:
        with open(INPUT_CSV, 'wb') as f:
            f.write(original_input)

    # Leave the required artifacts generated from the original input.
    run_script_and_compare()


def test_files_exist():
    assert os.path.isfile(CLEANED_CSV), f'{CLEANED_CSV} does not exist.'
    assert os.path.isfile(DROPPED_LOG), f'{DROPPED_LOG} does not exist.'


def test_dropped_log_content():
    expected_dropped = set()
    for i in range(1, 10001):
        if i % 73 == 0 or i % 191 == 0:
            expected_dropped.add(str(i))

    with open(DROPPED_LOG, 'r', encoding='utf-8') as f:
        dropped_ids = [line.strip() for line in f if line.strip()]

    assert len(dropped_ids) == len(expected_dropped), f'Expected {len(expected_dropped)} dropped IDs, found {len(dropped_ids)}.'
    assert set(dropped_ids) == expected_dropped, 'The dropped IDs do not match the expected malformed rows.'


def test_cleaned_csv_content_and_order():
    with open(CLEANED_CSV, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'date', 'text'], 'Header in cleaned.csv is incorrect.'
        rows = list(reader)

    assert len(rows) == 9812, f'Expected 9812 cleaned rows, found {len(rows)}.'

    previous_id = 0
    for row in rows:
        assert len(row) == 3, f'Row does not have exactly 3 columns: {row}'
        current_id = int(row[0])
        assert current_id > previous_id, 'Rows are not strictly ordered by id ascending.'
        previous_id = current_id
        text = row[2]
        assert '\\u' not in text, f'Found literal unicode escape in text: {text}'
        if current_id % 2 == 0:
            assert 'café' in text, f"Expected 'café' in text, got: {text}"
            assert '☃' in text, f"Expected '☃' (snowman) in text, got: {text}"


def test_exact_original_input_transformation():
    expected_rows, expected_dropped = expected_from_input()
    actual_rows, actual_dropped = read_outputs()
    assert actual_rows == expected_rows
    assert actual_dropped == expected_dropped
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
