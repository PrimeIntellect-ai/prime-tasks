#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import secrets
import stat
import subprocess

import numpy as np

SCRIPT = '/home/user/validate_etl.py'
INPUT = '/home/user/data/incoming.csv'
OUTPUTS = [
    '/home/user/schema_errors.log',
    '/home/user/overflow_errors.log',
    '/home/user/math_anomalies.log',
    '/home/user/valid_data.csv',
]

ORIGINAL_INPUT = '''id,x1,x2,model_output
1,2.0,3.0,11.5
2,foo,3.0,10.0
3,4.0,1.0,20.0
4,1e200,1.0,0.0
5,10.0,5.0,65.2
6,6.0,2.0,
7,0.0,0.0,1.5
8,1e250,1e250,1.0
9,-2.0,1.0,5.0
'''


def clean_outputs():
    for path in OUTPUTS:
        if os.path.lexists(path):
            os.remove(path)


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'validate_etl.py crashed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def read_log(path):
    assert os.path.exists(path), f'Expected log file {path} does not exist.'
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def setup_module():
    os.makedirs('/home/user/data', exist_ok=True)
    with open(INPUT, 'w', newline='') as f:
        f.write(ORIGINAL_INPUT)
    clean_outputs()
    run_script()


def test_script_exists_and_contains_required_numpy_configuration_and_handler():
    assert os.path.exists(SCRIPT), f'Expected script {SCRIPT} does not exist.'
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f'{SCRIPT} must be a regular file.'

    with open(SCRIPT, 'r') as f:
        tree = ast.parse(f.read(), filename=SCRIPT)

    numpy_names = set()
    direct_seterr_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'numpy':
                    numpy_names.add(alias.asname or 'numpy')
        elif isinstance(node, ast.ImportFrom) and node.module == 'numpy':
            for alias in node.names:
                if alias.name == 'seterr':
                    direct_seterr_names.add(alias.asname or 'seterr')

    found_seterr = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        is_seterr = (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == 'seterr'
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in numpy_names
        ) or (
            isinstance(node.func, ast.Name)
            and node.func.id in direct_seterr_names
        )
        if not is_seterr:
            continue
        kwargs = {
            kw.arg: kw.value.value
            for kw in node.keywords
            if kw.arg is not None and isinstance(kw.value, ast.Constant)
        }
        if kwargs.get('over') == 'raise' and kwargs.get('invalid') == 'raise':
            found_seterr = True
            break
    assert found_seterr, "Script must call numpy.seterr(over='raise', invalid='raise')."

    def is_floating_point_error(expr):
        return (
            isinstance(expr, ast.Name) and expr.id == 'FloatingPointError'
        ) or (
            isinstance(expr, ast.Attribute) and expr.attr == 'FloatingPointError'
        )

    handlers = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.ExceptHandler) and is_floating_point_error(node.type)
    ]
    assert handlers, 'Script must specifically catch FloatingPointError.'


def test_schema_errors_log():
    log_path = '/home/user/schema_errors.log'
    assert os.path.exists(log_path), f"Expected log file {log_path} does not exist."
    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = {'2', '6'}
    assert set(lines) == expected_ids, f"Expected schema errors {expected_ids}, but got {set(lines)}"


def test_overflow_errors_log():
    log_path = '/home/user/overflow_errors.log'
    assert os.path.exists(log_path), f"Expected log file {log_path} does not exist."
    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = {'4', '8'}
    assert set(lines) == expected_ids, f"Expected overflow errors {expected_ids}, but got {set(lines)}"


def test_math_anomalies_log():
    log_path = '/home/user/math_anomalies.log'
    assert os.path.exists(log_path), f"Expected log file {log_path} does not exist."
    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = {'3'}
    assert set(lines) == expected_ids, f"Expected math anomalies {expected_ids}, but got {set(lines)}"


def test_valid_data_csv():
    csv_path = '/home/user/valid_data.csv'
    assert os.path.exists(csv_path), f"Expected output file {csv_path} does not exist."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'x1', 'x2', 'model_output'], f"CSV header is incorrect: {header}"

        rows = list(reader)

    expected_ids = ['1', '5', '7', '9']
    actual_ids = [row[0] for row in rows if row]

    assert actual_ids == expected_ids, f"Expected valid data IDs {expected_ids} in order, but got {actual_ids}"

    # Keep the original integrity assertion and validate every remaining row too.
    assert rows[0] == ['1', '2.0', '3.0', '11.5'], f"First valid row data mismatch: {rows[0]}"
    assert rows == [
        ['1', '2.0', '3.0', '11.5'],
        ['5', '10.0', '5.0', '65.2'],
        ['7', '0.0', '0.0', '1.5'],
        ['9', '-2.0', '1.0', '5.0'],
    ], f'Valid row contents were not preserved: {rows}'


def reference_results(raw_rows):
    schema_ids = []
    overflow_ids = []
    anomaly_ids = []
    valid_rows = []

    for row in raw_rows:
        row_id = row[0]
        try:
            if any(value == '' for value in row):
                raise ValueError('empty field')
            int(row[0])
            x1 = np.float64(float(row[1]))
            x2 = np.float64(float(row[2]))
            model_output = np.float64(float(row[3]))
        except (TypeError, ValueError):
            schema_ids.append(row_id)
            continue

        try:
            with np.errstate(over='raise', invalid='raise'):
                expected = np.float64(0.5) * np.multiply(x1, x1) + np.float64(3.2) * x2
        except FloatingPointError:
            overflow_ids.append(row_id)
            continue

        if abs(float(model_output - expected)) > 1.5:
            anomaly_ids.append(row_id)
        else:
            valid_rows.append(row)

    return schema_ids, overflow_ids, anomaly_ids, valid_rows


def test_script_on_fresh_unpredictable_dataset():
    base = secrets.randbelow(700000000) + 100000000
    magnitude = secrets.randbelow(40) + 180
    rows = [
        [str(base + 1), '2.25', '-1.5', '-1.51875'],
        [str(base + 2), 'not-a-float', '3.0', '10.0'],
        [str(base + 3), '-4.0', '2.0', '16.0001'],
        [str(base + 4), f'1e{magnitude}', '1.0', '0.0'],
        [str(base + 5), '0.0', '0.0', '-1.5'],
        [str(base + 6), '6.0', '2.0', ''],
        [str(base + 7), '-2.0', '1.0', '5.0'],
    ]
    expected_schema, expected_overflow, expected_anomaly, expected_valid = reference_results(rows)

    with open(INPUT, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'x1', 'x2', 'model_output'])
        writer.writerows(rows)

    clean_outputs()
    run_script()

    actual_schema = read_log('/home/user/schema_errors.log')
    actual_overflow = read_log('/home/user/overflow_errors.log')
    actual_anomaly = read_log('/home/user/math_anomalies.log')
    assert len(actual_schema) == len(expected_schema) and set(actual_schema) == set(expected_schema)
    assert len(actual_overflow) == len(expected_overflow) and set(actual_overflow) == set(expected_overflow)
    assert len(actual_anomaly) == len(expected_anomaly) and set(actual_anomaly) == set(expected_anomaly)

    with open('/home/user/valid_data.csv', 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        actual_valid = list(reader)
    assert header == ['id', 'x1', 'x2', 'model_output']
    assert len(actual_valid) == len(expected_valid)

    for actual, expected in zip(actual_valid, expected_valid):
        assert len(actual) == 4
        assert actual[0] == expected[0]
        assert [float(value) for value in actual[1:]] == [float(value) for value in expected[1:]]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
