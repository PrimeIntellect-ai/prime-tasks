#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile
from pathlib import Path

import pytest

RAW_PATH = Path('/home/user/data/raw_data.csv')
CLEAN_PATH = Path('/home/user/data/clean_data.csv')
SOURCE_PATH = Path('/home/user/analyze.cpp')
RESULTS_PATH = Path('/home/user/results.txt')
SCRIPT_PATH = Path('/home/user/verify_results.sh')

EXPECTED_RAW_LINES = [
    'ID,Store_ID,Customers,Sales,Promo',
    '1,1,100,1500.50,1',
    '2,2,200,3200.00,0',
    '3,1,NA,NA,1',
    '4,1,120,1800.00,1',
    '5,2,210,3300.00,0',
    '6,3,50,800.00,0',
    '7,2,NA,3400.00,1',
    '8,3,60,950.00,1',
]
EXPECTED_CLEAN_LINES = [line for line in EXPECTED_RAW_LINES if 'NA' not in line]


def run_script():
    return subprocess.run([str(SCRIPT_PATH)], capture_output=True, text=True, timeout=10)


def expected_statistics(lines):
    rows = []
    for line in lines[1:]:
        fields = line.split(',')
        rows.append((int(fields[1]), float(fields[2]), float(fields[3])))

    mean_x = sum(row[1] for row in rows) / len(rows)
    mean_y = sum(row[2] for row in rows) / len(rows)
    numerator = sum((row[1] - mean_x) * (row[2] - mean_y) for row in rows)
    denominator = sum((row[1] - mean_x) ** 2 for row in rows)
    beta = numerator / denominator

    stores = {}
    for store, _, sale in rows:
        stores.setdefault(store, []).append(sale)
    averages = {store: sum(values) / len(values) for store, values in stores.items()}
    return beta, averages


def assert_results_match(lines):
    assert RESULTS_PATH.is_file(), 'The compiled program did not create /home/user/results.txt'
    content = RESULTS_PATH.read_text()
    assert 'NaN' not in content, "Results file still contains 'NaN'."

    output_lines = content.splitlines()
    beta, averages = expected_statistics(lines)
    assert len(output_lines) == 1 + len(averages), f'Unexpected results format: {content!r}'

    beta_match = re.fullmatch(r'Global Beta: (-?\d+\.\d{2})', output_lines[0])
    assert beta_match, f'Invalid Global Beta line: {output_lines[0]!r}'
    assert math.isclose(float(beta_match.group(1)), beta, abs_tol=0.011), (
        f'Incorrect beta: expected {beta:.2f}, got {beta_match.group(1)}'
    )

    seen = {}
    for line in output_lines[1:]:
        match = re.fullmatch(r'Store (\d+) Avg Sales: (-?\d+\.\d{2})', line)
        assert match, f'Invalid store result line: {line!r}'
        store = int(match.group(1))
        assert store not in seen, f'Duplicate output for store {store}'
        seen[store] = float(match.group(2))

    assert set(seen) == set(averages), f'Expected stores {sorted(averages)}, got {sorted(seen)}'
    for store, expected in averages.items():
        assert math.isclose(seen[store], expected, abs_tol=0.011), (
            f'Incorrect average for store {store}: expected {expected:.2f}, got {seen[store]:.2f}'
        )


def test_clean_data_csv_exists_and_valid():
    clean_data_path = '/home/user/data/clean_data.csv'
    assert os.path.isfile(clean_data_path), f'Cleaned data file not found at {clean_data_path}'

    with open(clean_data_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) > 0, 'clean_data.csv is empty'
    assert 'ID,Store_ID,Customers,Sales,Promo' in lines[0], 'Header row is missing or incorrect in clean_data.csv'

    for i, line in enumerate(lines):
        assert 'NA' not in line, f"Found 'NA' in clean_data.csv on line {i+1}: {line}"

    # Expecting 1 header + 6 valid rows
    assert len(lines) == 7, f'Expected 7 lines in clean_data.csv, found {len(lines)}'

    assert RAW_PATH.read_text().splitlines() == EXPECTED_RAW_LINES, 'The supplied raw dataset was modified'
    assert lines == EXPECTED_CLEAN_LINES, 'clean_data.csv is not exactly raw_data.csv with the NA rows removed'


def test_results_txt_exists_and_accurate():
    results_path = '/home/user/results.txt'
    assert os.path.isfile(results_path), f'Results file not found at {results_path}'

    with open(results_path, 'r') as f:
        content = f.read()

    assert 'NaN' not in content, "Results file still contains 'NaN'. The C++ bug was not completely fixed."

    expected_strings = [
        'Global Beta: 15.54',
        'Store 1 Avg Sales: 1650.25',
        'Store 2 Avg Sales: 3250.00',
        'Store 3 Avg Sales: 875.00'
    ]

    for expected in expected_strings:
        assert expected in content, f"Expected output '{expected}' not found in results.txt"


def test_verify_results_script():
    script_path = '/home/user/verify_results.sh'
    assert os.path.isfile(script_path), f'Test script not found at {script_path}'
    assert os.access(script_path, os.X_OK), f'Test script at {script_path} is not executable'

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f'verify_results.sh failed with exit code {result.returncode}. Output: {result.stdout} {result.stderr}'


def test_cpp_compiles_and_computes_clean_and_unseen_data():
    assert SOURCE_PATH.is_file(), f'C++ source not found at {SOURCE_PATH}'

    with tempfile.TemporaryDirectory() as temp_dir:
        binary = Path(temp_dir) / 'analyze_test_binary'
        compiled = subprocess.run(
            ['g++', '-std=c++17', '-O2', str(SOURCE_PATH), '-o', str(binary)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compiled.returncode == 0, f'analyze.cpp did not compile:\n{compiled.stdout}\n{compiled.stderr}'

        RESULTS_PATH.unlink(missing_ok=True)
        executed = subprocess.run(
            [str(binary), str(CLEAN_PATH)], capture_output=True, text=True, timeout=10
        )
        assert executed.returncode == 0, f'Program failed on clean_data.csv: {executed.stdout} {executed.stderr}'
        assert_results_match(EXPECTED_CLEAN_LINES)

        rng = random.SystemRandom()
        generated = ['ID,Store_ID,Customers,Sales,Promo']
        row_id = 1
        for store in range(1, 5):
            base_x = rng.randrange(25, 180)
            for offset in (0, rng.randrange(3, 25)):
                customers = base_x + offset
                sales = rng.randrange(400, 5000) + customers * rng.randrange(2, 12)
                generated.append(f'{row_id},{store},{customers},{sales},0')
                row_id += 1

        dynamic_csv = Path(temp_dir) / f'unseen_{rng.randrange(1 << 40)}.csv'
        dynamic_csv.write_text('\n'.join(generated) + '\n')
        RESULTS_PATH.unlink(missing_ok=True)
        executed = subprocess.run(
            [str(binary), str(dynamic_csv)], capture_output=True, text=True, timeout=10
        )
        assert executed.returncode == 0, f'Program failed on unseen CSV input: {executed.stdout} {executed.stderr}'
        assert_results_match(generated)


def test_verify_results_script_rejects_missing_and_nan_results():
    assert SCRIPT_PATH.is_file()
    assert os.access(SCRIPT_PATH, os.X_OK)
    saved = RESULTS_PATH.read_bytes()
    try:
        valid_result = run_script()
        assert valid_result.returncode == 0, 'verify_results.sh must accept an existing result without NaN'

        RESULTS_PATH.unlink()
        missing_result = run_script()
        assert missing_result.returncode == 1, 'verify_results.sh must exit 1 when results.txt is missing'

        RESULTS_PATH.write_text('Global Beta: NaN\n')
        nan_result = run_script()
        assert nan_result.returncode == 1, 'verify_results.sh must exit 1 when results.txt contains NaN'
    finally:
        RESULTS_PATH.write_bytes(saved)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
