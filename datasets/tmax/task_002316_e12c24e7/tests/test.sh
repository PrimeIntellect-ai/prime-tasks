#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import random
import subprocess
import uuid

CLEANER_DIR = '/home/user/cleaner'
DATA_PATH = '/home/user/data/users.csv'
RESULTS_PATH = '/home/user/results.json'


def run_cleaner():
    proc = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=CLEANER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        env={**os.environ, 'CARGO_TERM_COLOR': 'never'},
    )
    assert proc.returncode == 0, (
        f'Rust program failed with exit code {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert os.path.exists(RESULTS_PATH), 'Rust program did not create /home/user/results.json.'


def load_results():
    with open(RESULTS_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f'{RESULTS_PATH} is not valid JSON: {exc}'


def derive_expected(rows):
    anomalies = {'NaN', '-9999', ''}
    valid = [
        row for row in rows
        if all(row[key] not in anomalies for key in ('feature_a', 'feature_b', 'feature_c'))
    ]

    treatment = [float(row['feature_a']) for row in valid if row['group'] == 'Treatment']
    control = [float(row['feature_a']) for row in valid if row['group'] == 'Control']
    mean_diff = sum(treatment) / len(treatment) - sum(control) / len(control)

    target = next(row for row in valid if row['user_id'] == 'U_TARGET')
    target_values = [float(target[key]) for key in ('feature_a', 'feature_b', 'feature_c')]
    distances = []
    for row in valid:
        if row['user_id'] == 'U_TARGET':
            continue
        values = [float(row[key]) for key in ('feature_a', 'feature_b', 'feature_c')]
        distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(values, target_values)))
        distances.append((distance, row['user_id']))
    distances.sort(key=lambda item: item[0])
    return mean_diff, [user_id for _, user_id in distances[:3]]


def test_results_file_exists():
    assert os.path.exists('/home/user/results.json'), "The results file /home/user/results.json does not exist."


def test_results_content():
    results_path = '/home/user/results.json'
    assert os.path.exists(results_path), f"File {results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} is not a valid JSON file."

    assert "mean_diff" in data, "Key 'mean_diff' is missing from the results JSON."
    assert "similar_users" in data, "Key 'similar_users' is missing from the results JSON."

    expected_mean_diff = 29.133333333333333
    assert isinstance(data['mean_diff'], (int, float)), "mean_diff must be a number."
    assert math.isclose(data['mean_diff'], expected_mean_diff, rel_tol=1e-5), \
        f"mean_diff is incorrect. Expected ~{expected_mean_diff}, got {data['mean_diff']}"

    expected_similar_users = ["U_6", "U_1", "U_4"]
    assert isinstance(data['similar_users'], list), "similar_users must be a list."
    assert data['similar_users'] == expected_similar_users, \
        f"similar_users is incorrect. Expected {expected_similar_users}, got {data['similar_users']}"


def test_rust_program_processes_csv():
    cargo_toml = os.path.join(CLEANER_DIR, 'Cargo.toml')
    assert os.path.isfile(cargo_toml), 'No Cargo.toml exists under /home/user/cleaner/.'
    rust_sources = [
        path for path in glob.glob(os.path.join(CLEANER_DIR, '**', '*.rs'), recursive=True)
        if os.path.isfile(path) and os.path.getsize(path) > 0
    ]
    assert rust_sources, 'No non-empty Rust source file exists under /home/user/cleaner/.'

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:12]
    base_a = rng.uniform(20.0, 80.0)
    base_b = rng.uniform(-30.0, 30.0)
    base_c = rng.uniform(100.0, 180.0)
    d1 = rng.uniform(0.15, 0.25)
    d2 = rng.uniform(0.40, 0.55)
    d3 = rng.uniform(0.75, 0.95)

    nearest_1 = f'U_NEAR_A_{token}'
    nearest_2 = f'U_NEAR_B_{token}'
    nearest_3 = f'U_NEAR_C_{token}'
    rows = [
        {'user_id': 'U_TARGET', 'group': 'Control', 'feature_a': str(base_a), 'feature_b': str(base_b), 'feature_c': str(base_c)},
        {'user_id': nearest_1, 'group': 'Treatment', 'feature_a': str(base_a + d1), 'feature_b': str(base_b), 'feature_c': str(base_c)},
        {'user_id': nearest_2, 'group': 'Control', 'feature_a': str(base_a), 'feature_b': str(base_b + d2), 'feature_c': str(base_c)},
        {'user_id': nearest_3, 'group': 'Treatment', 'feature_a': str(base_a), 'feature_b': str(base_b), 'feature_c': str(base_c + d3)},
        {'user_id': f'U_FAR_T_{token}', 'group': 'Treatment', 'feature_a': str(base_a + rng.uniform(7.0, 11.0)), 'feature_b': str(base_b + 8.0), 'feature_c': str(base_c + 9.0)},
        {'user_id': f'U_FAR_C_{token}', 'group': 'Control', 'feature_a': str(base_a - rng.uniform(3.0, 6.0)), 'feature_b': str(base_b - 7.0), 'feature_c': str(base_c - 8.0)},
        {'user_id': f'U_BAD_NAN_{token}', 'group': 'Treatment', 'feature_a': 'NaN', 'feature_b': str(base_b), 'feature_c': str(base_c)},
        {'user_id': f'U_BAD_SENTINEL_{token}', 'group': 'Control', 'feature_a': str(base_a), 'feature_b': '-9999', 'feature_c': str(base_c)},
        {'user_id': f'U_BAD_EMPTY_{token}', 'group': 'Treatment', 'feature_a': str(base_a), 'feature_b': str(base_b), 'feature_c': ''},
    ]
    expected_mean, expected_users = derive_expected(rows)

    dynamic_error = None
    try:
        with open(DATA_PATH, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['user_id', 'group', 'feature_a', 'feature_b', 'feature_c'])
            writer.writeheader()
            writer.writerows(rows)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)

        run_cleaner()
        data = load_results()
        assert 'mean_diff' in data, "Key 'mean_diff' is missing from dynamically generated results."
        assert 'similar_users' in data, "Key 'similar_users' is missing from dynamically generated results."
        assert isinstance(data['mean_diff'], (int, float)), 'mean_diff must be a number.'
        assert math.isclose(data['mean_diff'], expected_mean, rel_tol=1e-9, abs_tol=1e-9), (
            f'Dynamic mean_diff is incorrect. Expected {expected_mean}, got {data["mean_diff"]}'
        )
        assert isinstance(data['similar_users'], list), 'similar_users must be a list.'
        assert data['similar_users'] == expected_users, (
            f'Dynamic similar_users is incorrect. Expected {expected_users}, got {data["similar_users"]}'
        )
    except BaseException as exc:
        dynamic_error = exc
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        try:
            run_cleaner()
        except BaseException:
            if dynamic_error is None:
                raise

    if dynamic_error is not None:
        raise dynamic_error
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
