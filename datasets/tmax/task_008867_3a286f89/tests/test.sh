#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
import math
import stat
import subprocess
import pytest

RAW_LOGS_PATH = '/home/user/data/raw_logs.jsonl'
CLEAN_LOGS_PATH = '/home/user/data/clean_logs.csv'
RESULTS_PATH = '/home/user/etl_output/results.json'
HOME_PATH = '/home/user'


def compute_expected_data():
    """Parse raw logs and compute expected intermediate data."""
    expected_rows = []
    with open(RAW_LOGS_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            # 1. lowercase
            text = row['text'].lower()
            # 2. remove punctuation (keep word chars and whitespace)
            text = re.sub(r'[^\w\s]', '', text)
            # 3. split by whitespace
            tokens = text.split()
            # 4. filter > 10
            if len(tokens) > 10:
                expected_rows.append({
                    'id': str(row['id']),
                    'experiment_group': row['experiment_group'],
                    'resolution_time': float(row['resolution_time']),
                    'token_count': len(tokens)
                })
    return expected_rows


def find_scripts(kind):
    scripts = []
    for entry in os.scandir(HOME_PATH):
        try:
            mode = os.lstat(entry.path).st_mode
        except OSError:
            continue
        if not stat.S_ISREG(mode):
            continue

        name = entry.name.lower()
        try:
            with open(entry.path, 'rb') as f:
                first_line = f.readline(256).decode('utf-8', errors='ignore').lower()
        except OSError:
            first_line = ''

        if kind == 'bash':
            if name.endswith(('.sh', '.bash')) or (first_line.startswith('#!') and ('bash' in first_line or '/sh' in first_line)):
                scripts.append(entry.path)
        elif kind == 'python':
            if name.endswith('.py') or (first_line.startswith('#!') and 'python' in first_line):
                scripts.append(entry.path)
    return sorted(scripts)


def run_stage(candidates, output_path, interpreter):
    attempts = []
    for script in candidates:
        if os.path.lexists(output_path):
            os.remove(output_path)
        try:
            proc = subprocess.run(
                [interpreter, script],
                cwd=HOME_PATH,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except Exception as exc:
            attempts.append(f'{script}: {exc}')
            continue

        if proc.returncode == 0 and os.path.isfile(output_path):
            return
        attempts.append(
            f'{script}: exit={proc.returncode}, output_exists={os.path.isfile(output_path)}, stderr={proc.stderr[-500:]}'
        )

    pytest.fail(f'No submitted {interpreter} script successfully created {output_path}. Attempts: {attempts}')


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_pipeline():
    bash_scripts = find_scripts('bash')
    python_scripts = find_scripts('python')

    assert bash_scripts, 'No Bash script was found directly under /home/user.'
    assert python_scripts, 'No Python script was found directly under /home/user.'

    os.makedirs(os.path.dirname(CLEAN_LOGS_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(RESULTS_PATH), exist_ok=True)

    run_stage(bash_scripts, CLEAN_LOGS_PATH, '/bin/bash')
    run_stage(python_scripts, RESULTS_PATH, '/usr/bin/python3')


def test_clean_logs_csv():
    """Validate the clean_logs.csv file structure and contents."""
    assert os.path.isfile(CLEAN_LOGS_PATH), f"File {CLEAN_LOGS_PATH} does not exist."

    expected_rows = compute_expected_data()

    with open(CLEAN_LOGS_PATH, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == ['id', 'experiment_group', 'resolution_time', 'token_count'], \
            f"CSV headers are incorrect. Got: {headers}"

        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in CSV, got {len(actual_rows)}."

    expected_dict = {r['id']: r for r in expected_rows}
    actual_ids = [row[0] for row in actual_rows]
    assert len(actual_ids) == len(set(actual_ids)), \
        "clean_logs.csv contains duplicate IDs."
    assert set(actual_ids) == set(expected_dict), \
        "clean_logs.csv does not contain exactly the expected set of IDs."

    for row in actual_rows:
        row_id = row[0]
        assert row_id in expected_dict, f"Unexpected ID {row_id} in clean_logs.csv"
        exp = expected_dict[row_id]
        assert row[1] == exp['experiment_group'], f"Group mismatch for ID {row_id}"
        assert math.isclose(float(row[2]), exp['resolution_time'], rel_tol=1e-5), \
            f"Resolution time mismatch for ID {row_id}"
        assert int(row[3]) == exp['token_count'], f"Token count mismatch for ID {row_id}"


def test_results_json():
    """Validate the results.json file structure and calculated metrics."""
    assert os.path.isfile(RESULTS_PATH), f"File {RESULTS_PATH} does not exist."

    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    expected_keys = {
        "valid_records", "group_a_mean", "group_b_mean",
        "ci_lower", "ci_upper", "p_value"
    }
    assert set(results.keys()) == expected_keys, \
        f"results.json keys mismatch. Expected {expected_keys}, got {set(results.keys())}"

    expected_rows = compute_expected_data()

    group_a = [r['resolution_time'] for r in expected_rows if r['experiment_group'] == 'A']
    group_b = [r['resolution_time'] for r in expected_rows if r['experiment_group'] == 'B']

    mean_a = sum(group_a) / len(group_a)
    mean_b = sum(group_b) / len(group_b)

    assert results["valid_records"] == len(expected_rows), \
        f"valid_records mismatch. Expected {len(expected_rows)}, got {results['valid_records']}"

    assert math.isclose(results["group_a_mean"], round(mean_a, 4), rel_tol=1e-4), \
        f"group_a_mean mismatch. Expected {round(mean_a, 4)}, got {results['group_a_mean']}"

    assert math.isclose(results["group_b_mean"], round(mean_b, 4), rel_tol=1e-4), \
        f"group_b_mean mismatch. Expected {round(mean_b, 4)}, got {results['group_b_mean']}"

    # Verify the specific statistical values based on the deterministic seed.
    assert math.isclose(results["ci_lower"], 2.5833, rel_tol=1e-3), \
        f"ci_lower mismatch. Expected ~2.5833, got {results['ci_lower']}"

    assert math.isclose(results["ci_upper"], 7.0583, rel_tol=1e-3), \
        f"ci_upper mismatch. Expected ~7.0583, got {results['ci_upper']}"

    assert math.isclose(results["p_value"], 0.0000, abs_tol=1e-4), \
        f"p_value mismatch. Expected ~0.0000, got {results['p_value']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
