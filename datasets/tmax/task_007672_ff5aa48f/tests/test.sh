#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import subprocess

SCRIPT = '/home/user/etl_test.py'
DATA = '/home/user/data.csv'
WEIGHTS = '/home/user/weights.json'
RESULTS = '/home/user/results.txt'


def run_script():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f'etl_test.py exited with status {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert os.path.exists(RESULTS), f'{RESULTS} not found. The script did not generate the output file.'


def parse_exact_results():
    with open(RESULTS, 'r') as f:
        content = f.read()
    match = re.fullmatch(
        r'Trace: (-?\d+\.\d{2})\nMean_Prediction: (-?\d+\.\d{2})\n?',
        content,
    )
    assert match, f'results.txt is not in the required exact two-line, two-decimal format:\n{content}'
    return float(match.group(1)), float(match.group(2))


def test_etl_script_exists():
    script_file = '/home/user/etl_test.py'
    assert os.path.exists(script_file), f'{script_file} not found. You must write the ETL script to this location.'
    assert os.path.isfile(script_file), f'{script_file} must be a Python script file.'
    assert os.path.getsize(script_file) > 0, f'{script_file} is empty.'


def test_results_txt_content():
    run_script()
    results_file = '/home/user/results.txt'
    assert os.path.exists(results_file), f'{results_file} not found. The script did not generate the output file.'

    with open(results_file, 'r') as f:
        content = f.read().strip()

    assert 'Trace: 29.83' in content, f"Incorrect trace in results.txt. Expected 'Trace: 29.83', got:\n{content}"
    assert 'Mean_Prediction: 11.75' in content, f"Incorrect mean prediction in results.txt. Expected 'Mean_Prediction: 11.75', got:\n{content}"
    assert content == 'Trace: 29.83\nMean_Prediction: 11.75', f'Unexpected extra or malformed content in results.txt:\n{content}'


def expected_values(rows, weights):
    xs = [float(row[0]) for row in rows]
    ys = [float(row[1]) for row in rows]
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    var_x = sum((x - mean_x) ** 2 for x in xs) / (len(xs) - 1)
    var_y = sum((y - mean_y) ** 2 for y in ys) / (len(ys) - 1)
    trace = var_x + var_y
    mean_prediction = sum(
        x * weights[0] + y * weights[1] for x, y in zip(xs, ys)
    ) / len(xs)
    return trace, mean_prediction


def test_schema_covariance_and_inference_on_fresh_inputs():
    rng = secrets.SystemRandom()
    original_data = open(DATA, 'rb').read()
    original_weights = open(WEIGHTS, 'rb').read()

    try:
        for _ in range(2):
            valid_rows = []
            used_x = set()
            while len(valid_rows) < 6:
                x = rng.randint(-40, 60)
                if x in used_x:
                    continue
                used_x.add(x)
                y = rng.randint(-100, 120) / 4.0
                valid_rows.append((x, y))

            weights = [rng.randint(-250, 250) / 100.0, rng.randint(-250, 250) / 100.0]
            expected_trace, expected_mean = expected_values(valid_rows, weights)

            with open(DATA, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['X', 'Y', 'Label'])
                for i, (x, y) in enumerate(valid_rows):
                    writer.writerow([x, y, f'ignored-{i}'])
                writer.writerow(['not_an_integer', 9.25, 'must-drop'])
                writer.writerow([17, 'not_a_float', 'must-drop'])
                writer.writerow(['', 3.5, 'must-drop'])
                writer.writerow([22, '', 'must-drop'])

            with open(WEIGHTS, 'w') as f:
                json.dump(weights, f)

            run_script()
            actual_trace, actual_mean = parse_exact_results()
            assert abs(actual_trace - expected_trace) <= 0.0051, (
                f'Incorrect sample covariance trace: expected {expected_trace:.8f}, '
                f'got {actual_trace:.2f}'
            )
            assert abs(actual_mean - expected_mean) <= 0.0051, (
                f'Incorrect mean prediction: expected {expected_mean:.8f}, '
                f'got {actual_mean:.2f}'
            )
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)
        with open(WEIGHTS, 'wb') as f:
            f.write(original_weights)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
