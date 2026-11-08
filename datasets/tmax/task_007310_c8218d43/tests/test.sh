#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess


def parse_train_data(filepath):
    valid_rows = []
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) != 7:
                continue
            try:
                id_val = int(row[0])
                label = int(row[1])
                if label not in (0, 1):
                    continue
                v = [float(x) for x in row[2:7]]
                valid_rows.append((id_val, label, v))
            except ValueError:
                continue
    return valid_rows


def parse_test_data(filepath):
    rows = []
    with open(filepath, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) != 6:
                continue
            try:
                id_val = int(row[0])
                v = [float(x) for x in row[1:6]]
                rows.append((id_val, v))
            except ValueError:
                continue
    return rows


def dist(v1, v2):
    return sum((a - b) ** 2 for a, b in zip(v1, v2))


def knn_predict(train_data, test_point, k):
    distances = []
    for row in train_data:
        d = dist(row[2], test_point)
        distances.append((d, row[0], row[1]))
    distances.sort(key=lambda x: (x[0], x[1]))
    top_k = distances[:k]
    votes = [x[2] for x in top_k]
    count_1 = sum(votes)
    count_0 = k - count_1
    return 1 if count_1 > count_0 else 0


def expected_for(train_data, test_data):
    folds = {0: [], 1: [], 2: []}
    for i, row in enumerate(train_data):
        folds[i % 3].append(row)

    best_k = None
    best_acc = -1
    for k in [1, 3, 5, 7]:
        correct = 0
        total = 0
        for i in range(3):
            val_set = folds[i]
            train_set = folds[(i + 1) % 3] + folds[(i + 2) % 3]
            for val_row in val_set:
                pred = knn_predict(train_set, val_row[2], k)
                if pred == val_row[1]:
                    correct += 1
                total += 1
        acc = correct / total
        if acc > best_acc:
            best_acc = acc
            best_k = k

    predictions = []
    for test_row in test_data:
        predictions.append((test_row[0], knn_predict(train_data, test_row[1], best_k)))
    return best_k, predictions


def get_expected_results():
    train_data = parse_train_data('/home/user/train.csv')
    test_data = parse_test_data('/home/user/test.csv')
    return expected_for(train_data, test_data)


def test_best_k_file():
    best_k_path = '/home/user/best_k.txt'
    assert os.path.exists(best_k_path), f"File {best_k_path} is missing."

    with open(best_k_path, 'r') as f:
        content = f.read().strip()

    expected_k, _ = get_expected_results()
    assert content.isdigit(), f"Content of {best_k_path} is not an integer: '{content}'"
    assert int(content) == expected_k, f"Expected best k to be {expected_k}, but got {content}."


def test_predictions_file():
    preds_path = '/home/user/predictions.csv'
    assert os.path.exists(preds_path), f"File {preds_path} is missing."

    _, expected_preds = get_expected_results()
    expected_dict = dict(expected_preds)

    with open(preds_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'label'], f"Expected header ['id', 'label'], got {header}"

        actual_preds = {}
        for row in reader:
            assert len(row) == 2, f"Malformed row in predictions.csv: {row}"
            actual_preds[int(row[0])] = int(row[1])

    assert len(actual_preds) == len(expected_dict), f"Expected {len(expected_dict)} predictions, got {len(actual_preds)}"
    for test_id, expected_label in expected_dict.items():
        assert test_id in actual_preds, f"Prediction for id {test_id} is missing."
        assert actual_preds[test_id] == expected_label, f"Expected label {expected_label} for id {test_id}, got {actual_preds[test_id]}."


def make_candidate(rng, case_number):
    rows = []
    base_id = 10000 + case_number * 100
    for i in range(24):
        label = rng.randrange(2)
        if i == 0:
            label = 0
        elif i == 1:
            label = 1
        values = [round(rng.uniform(-3.0, 3.0), 6) for _ in range(5)]
        rows.append((base_id + i * 7, label, values))
    tests = []
    for i in range(8):
        values = [round(rng.uniform(-3.2, 3.2), 6) for _ in range(5)]
        tests.append((base_id + 5000 + i * 11, values))
    return rows, tests


def write_case(train_rows, test_rows):
    invalid_lines = [
        'not_an_id,0,0,0,0,0,0',
        '77777,2,0,0,0,0,0',
        '88888,1,0,not_a_number,0,0,0',
        'malformed,row',
        '99999,0,0,0,0,0,0,extra',
    ]
    with open('/home/user/train.csv', 'w', newline='') as f:
        f.write('id,label,v1,v2,v3,v4,v5\n')
        for i, (row_id, label, values) in enumerate(train_rows):
            if i < len(invalid_lines):
                f.write(invalid_lines[i] + '\n')
            f.write(','.join([str(row_id), str(label)] + [format(x, '.6f') for x in values]) + '\n')
        f.write('12345,0,1,2,3\n')

    with open('/home/user/test.csv', 'w', newline='') as f:
        f.write('id,v1,v2,v3,v4,v5\n')
        for row_id, values in test_rows:
            f.write(','.join([str(row_id)] + [format(x, '.6f') for x in values]) + '\n')


def read_generated_outputs(expected_k, expected_predictions):
    with open('/home/user/best_k.txt', 'r') as f:
        content = f.read().strip()
    assert content.isdigit(), f"best_k.txt is not an integer on held-out data: {content!r}"
    assert int(content) == expected_k, f"Held-out data expected k={expected_k}, got {content}"

    with open('/home/user/predictions.csv', 'r', newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['id', 'label'], f"Bad predictions header on held-out data: {rows[:1]}"
    actual = []
    for row in rows[1:]:
        assert len(row) == 2, f"Malformed held-out prediction row: {row}"
        actual.append((int(row[0]), int(row[1])))
    assert actual == expected_predictions, f"Held-out predictions differ: expected {expected_predictions}, got {actual}"


def test_solution_cpp_compiles_and_handles_unseen_inputs():
    source = '/home/user/solution.cpp'
    executable = '/tmp/knn_submission'
    assert os.path.isfile(source), f"Required C++ source file {source} is missing or is not a regular file."
    if os.path.exists(executable):
        os.remove(executable)

    compiled = subprocess.run(
        ['g++', '-O3', '-std=c++17', source, '-o', executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f"solution.cpp failed to compile:\n{compiled.stderr}"

    rng = random.Random(secrets.randbits(128))
    cases = []
    seen_k = set()
    for attempt in range(500):
        train_rows, test_rows = make_candidate(rng, attempt)
        k, predictions = expected_for(train_rows, test_rows)
        if k not in seen_k or len(cases) < 2:
            cases.append((train_rows, test_rows, k, predictions))
            seen_k.add(k)
        if len(cases) >= 4 and len(seen_k) >= 2:
            break
    assert len(cases) >= 2

    for train_rows, test_rows, expected_k, expected_predictions in cases:
        write_case(train_rows, test_rows)
        for path in ('/home/user/best_k.txt', '/home/user/predictions.csv'):
            if os.path.exists(path):
                os.remove(path)
        run = subprocess.run(
            [executable],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert run.returncode == 0, f"Compiled program failed on held-out input:\n{run.stderr}"
        assert os.path.isfile('/home/user/best_k.txt'), 'Program did not create best_k.txt on held-out input.'
        assert os.path.isfile('/home/user/predictions.csv'), 'Program did not create predictions.csv on held-out input.'
        read_generated_outputs(expected_k, expected_predictions)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
