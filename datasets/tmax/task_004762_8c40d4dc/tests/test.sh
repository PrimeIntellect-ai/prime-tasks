#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
from pathlib import Path

import pandas as pd
import pytest

SCRIPT_PATH = Path('/home/user/etl_pipeline.sh')
RESULTS_PATH = Path('/home/user/results.csv')


def test_etl_pipeline_script_exists():
    script_path = '/home/user/etl_pipeline.sh'
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_results_csv_exists():
    results_path = '/home/user/results.csv'
    assert os.path.exists(results_path), f"The output file {results_path} does not exist."
    assert os.path.isfile(results_path), f"The path {results_path} is not a file."


def test_results_csv_metric():
    results_path = '/home/user/results.csv'
    assert os.path.exists(results_path), f"The output file {results_path} does not exist."

    try:
        pred_df = pd.read_csv(results_path)
    except Exception as e:
        pytest.fail(f"Failed to read {results_path} as a CSV: {e}")

    expected_columns = ['ID', 'Score']
    actual_columns = list(pred_df.columns)
    assert actual_columns == expected_columns, f"Expected columns {expected_columns}, but got {actual_columns}."

    true_data = {
        1: 8.25,
        2: 16.525,
        3: 6.0,
        4: 25.225,
        5: 12.25
    }

    ids = pred_df['ID'].astype(int).tolist()
    assert ids == [1, 2, 3, 4, 5], f"Expected IDs [1, 2, 3, 4, 5] in order, but got {ids}."

    mse = 0.0
    for _, row in pred_df.iterrows():
        i = int(row['ID'])
        if i in true_data:
            try:
                score = float(row['Score'])
            except ValueError:
                pytest.fail(f"Score for ID {i} is not a valid float: {row['Score']}")
            mse += (score - true_data[i]) ** 2
        else:
            pytest.fail(f"Unexpected ID {i} found in {results_path}.")

    mse = mse / len(true_data)
    threshold = 0.05
    assert mse <= threshold, f"Calculated MSE {mse} exceeds the allowed threshold of {threshold}."


def write_inputs(rows_a, rows_b):
    with open('/app/table_a.tsv', 'w', encoding='utf-8', newline='') as f:
        f.write('ID\tF1\tF2\n')
        for row in rows_a:
            f.write(f'{row[0]}\t{row[1]}\t{row[2]}\n')

    with open('/app/table_b.csv', 'w', encoding='utf-8', newline='') as f:
        f.write('ID,F3\n')
        for row in rows_b:
            f.write(f'{row[0]},{row[1]}\n')


def write_config(params):
    text = (
        f"PRIOR_A: {params['PRIOR_A']}\n"
        f"PRIOR_B: {params['PRIOR_B']}\n"
        f"W1: {params['W1']}\n"
        f"W2: {params['W2']}\n"
        f"W3: {params['W3']}"
    )
    draw = "text 20,40 '" + text + "'"
    proc = subprocess.run(
        [
            'convert', '-size', '400x300', 'xc:white',
            '-font', 'DejaVu-Sans', '-pointsize', '24', '-fill', 'black',
            '-draw', draw, '/app/config_matrix.png'
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, f'Failed to create test configuration image: {proc.stderr}'


def expected_scores(rows_a, rows_b, params):
    a = {int(i): (float(f1), float(f2)) for i, f1, f2 in rows_a}
    b = {int(i): float(f3) for i, f3 in rows_b}
    expected = {}
    for i in sorted(set(a) & set(b)):
        f1, f2 = a[i]
        f3 = b[i]
        expected[i] = (
            float(params['PRIOR_A']) * (float(params['W1']) * f1 + float(params['W2']) * f2)
            + float(params['PRIOR_B']) * (float(params['W3']) * f3)
        )
    return expected


def assert_results(expected):
    assert RESULTS_PATH.exists(), 'Pipeline did not create /home/user/results.csv.'
    assert RESULTS_PATH.is_file(), '/home/user/results.csv is not a file.'
    try:
        frame = pd.read_csv(RESULTS_PATH)
    except Exception as e:
        pytest.fail(f'Failed to read pipeline output as CSV: {e}')

    assert list(frame.columns) == ['ID', 'Score'], \
        f"Expected columns ['ID', 'Score'], but got {list(frame.columns)}."
    assert len(frame) == len(expected), \
        f'Expected {len(expected)} joined rows, but got {len(frame)}.'

    try:
        ids = frame['ID'].astype(int).tolist()
    except Exception as e:
        pytest.fail(f'Output IDs are not valid integers: {e}')
    assert ids == sorted(expected), f'Expected sorted IDs {sorted(expected)}, but got {ids}.'

    squared_error = 0.0
    for _, row in frame.iterrows():
        i = int(row['ID'])
        try:
            score = float(row['Score'])
        except (TypeError, ValueError) as e:
            pytest.fail(f'Score for ID {i} is not a valid float: {e}')
        assert math.isfinite(score), f'Score for ID {i} is not finite.'
        squared_error += (score - expected[i]) ** 2

    mse = squared_error / len(expected)
    assert mse <= 0.05, f'Calculated MSE {mse} exceeds the allowed threshold of 0.05.'


def run_pipeline():
    proc = subprocess.run(
        ['/bin/bash', str(SCRIPT_PATH)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    assert proc.returncode == 0, (
        f'Pipeline exited with status {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )


def test_script_is_shell_and_processes_changed_inputs_and_images():
    raw = SCRIPT_PATH.read_bytes()
    assert raw, 'The pipeline script is empty.'
    assert b'\x00' not in raw, 'The pipeline script is not a text shell script.'

    syntax = subprocess.run(
        ['/bin/bash', '-n', str(SCRIPT_PATH)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert syntax.returncode == 0, f'The pipeline is not valid Bash: {syntax.stderr}'

    source = raw.decode('utf-8', errors='replace')
    active_source = '\n'.join(
        line for line in source.splitlines() if not line.lstrip().startswith('#')
    )
    forbidden = re.compile(
        r'(?im)(?:^\s*|[;&|]\s*|\b(?:exec|command|env|sudo)\s+)'
        r'(?:/usr/bin/|/bin/)?(?:python(?:[0-9.]*)?|perl|Rscript|R)(?=\s|$)'
    )
    assert not forbidden.search(active_source), \
        'The pipeline invokes Python, Perl, or R instead of Bash/POSIX CLI processing.'

    protected = [
        Path('/app/table_a.tsv'),
        Path('/app/table_b.csv'),
        Path('/app/config_matrix.png'),
    ]
    backups = {path: path.read_bytes() for path in protected}

    rows_a = [
        (6, 9, 4),
        (2, 13, 7),
        (4, 5, 16),
        (1, 21, 3),
        (3, 99, 99),
    ]
    rows_b = [
        (4, 8),
        (1, 11),
        (6, 2),
        (2, 14),
        (5, 77),
    ]
    configs = [
        {'PRIOR_A': '0.42', 'PRIOR_B': '0.58', 'W1': '1.25', 'W2': '-0.75', 'W3': '2.4'},
        {'PRIOR_A': '0.60', 'PRIOR_B': '0.40', 'W1': '0.8', 'W2': '1.1', 'W3': '-1.5'},
    ]

    try:
        write_inputs(rows_a, rows_b)
        for params in configs:
            write_config(params)
            if RESULTS_PATH.exists():
                RESULTS_PATH.unlink()
            run_pipeline()
            assert_results(expected_scores(rows_a, rows_b, params))
    finally:
        for path, content in backups.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
