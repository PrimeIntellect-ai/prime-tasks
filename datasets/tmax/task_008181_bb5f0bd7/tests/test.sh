#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import secrets
import shutil
import stat
import subprocess

SCRIPTS = [
    '/home/user/clean.py',
    '/home/user/recommend.py',
    '/home/user/evaluate.sh'
]


def test_scripts_exist_and_executable():
    for script in SCRIPTS:
        assert os.path.exists(script), f"Script {script} is missing."
        assert stat.S_ISREG(os.stat(script).st_mode), f"Script {script} is not a regular file."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_clean_features_csv():
    filepath = '/home/user/clean_features.csv'
    assert os.path.exists(filepath), f"{filepath} is missing."

    expected_data = {
        'A': [1.0, -10.0, 0.1],
        'B': [2.0, 1.0, 0.2],
        'C': [10.0, 1.5, 0.3],
        'D': [10.0, 2.0, 0.4],
        'E': [1.5, -10.0, 0.5],
    }

    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'f1', 'f2', 'f3'], f"Incorrect header in {filepath}."

        parsed_data = {}
        for row in reader:
            assert len(row) == 4, f"Row {row} does not have 4 columns."
            parsed_data[row[0]] = [float(x) for x in row[1:]]
            for val in row[1:]:
                assert len(val.split('.')[-1]) == 4, f"Value {val} is not formatted to 4 decimal places."

    assert set(parsed_data.keys()) == set(expected_data.keys()), "Missing or extra IDs in cleaned features."

    for k, v in expected_data.items():
        for expected_val, actual_val in zip(v, parsed_data[k]):
            assert math.isclose(expected_val, actual_val, rel_tol=1e-5), f"Incorrect cleaned value for {k}: expected {expected_val}, got {actual_val}."


def test_nn_results_csv():
    filepath = '/home/user/nn_results.csv'
    assert os.path.exists(filepath), f"{filepath} is missing."

    expected_nn = {
        'A': ['E', 'B'],
        'B': ['C', 'D'],
        'C': ['D', 'B'],
        'D': ['C', 'B'],
        'E': ['A', 'B'],
    }

    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'nn1_id', 'nn2_id'], f"Incorrect header in {filepath}."

        parsed_nn = {}
        for row in reader:
            assert len(row) == 3, f"Row {row} does not have 3 columns."
            parsed_nn[row[0]] = [row[1], row[2]]

    assert parsed_nn == expected_nn, f"Incorrect nearest neighbors. Expected {expected_nn}, got {parsed_nn}."


def test_accuracy_txt():
    filepath = '/home/user/accuracy.txt'
    assert os.path.exists(filepath), f"{filepath} is missing."

    with open(filepath, 'r') as f:
        content = f.read().strip()

    assert content == "0.20", f"Incorrect accuracy in {filepath}. Expected '0.20', got '{content}'."


def run_checked(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (
        f"Command {command} failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_scripts_execute_and_generalize_to_unseen_data(tmp_path):
    paths = [
        '/home/user/features.csv',
        '/home/user/baseline_nn.csv',
        '/home/user/clean_features.csv',
        '/home/user/nn_results.csv',
        '/home/user/accuracy.txt',
    ]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            backup = tmp_path / (os.path.basename(path) + '.backup')
            shutil.copy2(path, backup)
            backups[path] = backup

    rng = random.SystemRandom()
    try:
        # Generate an unpredictable cleaning input containing a missing value,
        # a positive outlier, and a negative outlier in every feature column.
        ids = []
        while len(ids) < 7:
            candidate = 'I' + secrets.token_hex(4)
            if candidate not in ids:
                ids.append(candidate)

        raw = []
        for i in range(len(ids)):
            row = []
            for j in range(3):
                if i == j:
                    row.append(None)
                elif i == j + 1:
                    row.append(rng.randint(1500, 3000) / 100.0)
                elif i == j + 2:
                    row.append(-rng.randint(1500, 3000) / 100.0)
                else:
                    row.append(rng.randint(-900, 900) / 100.0)
            raw.append(row)

        with open('/home/user/features.csv', 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'f1', 'f2', 'f3'])
            for item_id, values in zip(ids, raw):
                writer.writerow([item_id] + ['' if value is None else str(value) for value in values])

        means = []
        for column in range(3):
            present = [row[column] for row in raw if row[column] is not None]
            means.append(sum(present) / len(present))

        expected_clean = {}
        for item_id, values in zip(ids, raw):
            cleaned = []
            for column, value in enumerate(values):
                if value is None:
                    value = means[column]
                value = max(-10.0, min(10.0, value))
                cleaned.append(f'{value:.4f}')
            expected_clean[item_id] = cleaned

        os.remove('/home/user/clean_features.csv')
        run_checked(['python3', '/home/user/clean.py'])
        assert os.path.isfile('/home/user/clean_features.csv'), 'clean.py did not create clean_features.csv'

        with open('/home/user/clean_features.csv', newline='') as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ['id', 'f1', 'f2', 'f3']
        assert len(rows) == len(ids) + 1, 'clean.py produced missing or extra rows'
        actual_clean = {}
        for row in rows[1:]:
            assert len(row) == 4
            assert row[0] not in actual_clean, f'Duplicate cleaned ID {row[0]}'
            for value in row[1:]:
                whole, dot, fraction = value.partition('.')
                assert dot == '.' and len(fraction) == 4, f'{value!r} is not formatted to four decimal places'
                float(value)
            actual_clean[row[0]] = row[1:]
        assert actual_clean == expected_clean, f'clean.py failed on unseen data: {actual_clean!r}'

        # Execute recommendation on the newly generated clean data and derive
        # the expected neighbors independently from that data.
        points = {item_id: [float(x) for x in values] for item_id, values in actual_clean.items()}
        expected_nn = {}
        for item_id, point in points.items():
            candidates = []
            for other_id, other in points.items():
                if other_id == item_id:
                    continue
                distance_squared = sum((a - b) ** 2 for a, b in zip(point, other))
                candidates.append((distance_squared, other_id))
            candidates.sort(key=lambda pair: (pair[0], pair[1]))
            expected_nn[item_id] = [candidates[0][1], candidates[1][1]]

        if os.path.exists('/home/user/nn_results.csv'):
            os.remove('/home/user/nn_results.csv')
        run_checked(['python3', '/home/user/recommend.py'])
        assert os.path.isfile('/home/user/nn_results.csv'), 'recommend.py did not create nn_results.csv'
        with open('/home/user/nn_results.csv', newline='') as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ['id', 'nn1_id', 'nn2_id']
        assert len(rows) == len(ids) + 1, 'recommend.py produced missing or extra rows'
        actual_nn = {}
        for row in rows[1:]:
            assert len(row) == 3
            assert row[0] not in actual_nn, f'Duplicate recommendation ID {row[0]}'
            actual_nn[row[0]] = row[1:]
        assert actual_nn == expected_nn, f'recommend.py failed on unseen data: {actual_nn!r}'

        # Replace both recommendation files with an unpredictable validation
        # case. Rows are deliberately in different orders and matching pairs
        # are reversed to require ID-based, order-insensitive set comparison.
        eval_ids = ['E' + secrets.token_hex(4) for _ in range(7)]
        match_count = rng.randint(1, len(eval_ids) - 1)
        new_rows = []
        baseline_rows = []
        for index, item_id in enumerate(eval_ids):
            first = 'N' + secrets.token_hex(4)
            second = 'N' + secrets.token_hex(4)
            new_rows.append([item_id, first, second])
            if index < match_count:
                baseline_rows.append([item_id, second, first])
            else:
                baseline_rows.append([item_id, first, 'X' + secrets.token_hex(4)])
        rng.shuffle(new_rows)
        rng.shuffle(baseline_rows)

        with open('/home/user/nn_results.csv', 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'nn1_id', 'nn2_id'])
            writer.writerows(new_rows)
        with open('/home/user/baseline_nn.csv', 'w', newline='') as f:
            writer = csv.writer(f, lineterminator='\n')
            writer.writerow(['id', 'nn1_id', 'nn2_id'])
            writer.writerows(baseline_rows)

        if os.path.exists('/home/user/accuracy.txt'):
            os.remove('/home/user/accuracy.txt')
        run_checked(['bash', '/home/user/evaluate.sh'])
        assert os.path.isfile('/home/user/accuracy.txt'), 'evaluate.sh did not create accuracy.txt'
        with open('/home/user/accuracy.txt') as f:
            accuracy = f.read().strip()
        expected_accuracy = f'{match_count / len(eval_ids):.2f}'
        assert accuracy == expected_accuracy, (
            f'evaluate.sh returned {accuracy!r}; expected {expected_accuracy!r} on unseen data'
        )
    finally:
        for path in paths:
            if path in backups:
                shutil.copy2(backups[path], path)
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
