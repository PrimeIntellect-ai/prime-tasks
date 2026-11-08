#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import subprocess

JOINED = "/home/user/data/joined.csv"
FINAL = "/home/user/final_mse.txt"
SOURCE = "/home/user/pipeline.cpp"
BINARY = "/tmp/submission_pipeline"


def mean(values):
    return sum(values) / len(values)


def std(values, mu, ddof=0):
    return math.sqrt(sum((x - mu) ** 2 for x in values) / (len(values) - ddof))


def corr(x, y, mx, my, sx, sy):
    if sx == 0 or sy == 0:
        return 0.0
    covariance = sum((a - mx) * (b - my) for a, b in zip(x, y)) / len(x)
    return covariance / (sx * sy)


def expected_mses(dataset):
    n = len(dataset)
    assert n % 5 == 0
    fold_size = n // 5
    results = []

    for ddof in (0, 1):
        fold_mses = []
        for fold in range(5):
            val_indices = list(range(fold * fold_size, (fold + 1) * fold_size))
            val_set = set(val_indices)
            train_indices = [i for i in range(n) if i not in val_set]

            train_features = [[dataset[i][j] for i in train_indices] for j in range(3)]
            val_features = [[dataset[i][j] for i in val_indices] for j in range(3)]
            train_targets = [dataset[i][3] for i in train_indices]
            val_targets = [dataset[i][3] for i in val_indices]

            feature_means = [mean(col) for col in train_features]
            feature_stds = [std(col, feature_means[j], ddof) for j, col in enumerate(train_features)]
            target_mean = mean(train_targets)
            target_std = std(train_targets, target_mean, ddof)

            normalized_train = [
                [(x - feature_means[j]) / feature_stds[j] for x in train_features[j]]
                for j in range(3)
            ]
            normalized_val = [
                [(x - feature_means[j]) / feature_stds[j] for x in val_features[j]]
                for j in range(3)
            ]

            weights = []
            for col in normalized_train:
                col_mean = mean(col)
                col_std = std(col, col_mean, 0)
                weights.append(corr(col, train_targets, col_mean, target_mean, col_std, target_std))

            squared_error = 0.0
            for j, target in enumerate(val_targets):
                prediction = sum(weights[k] * normalized_val[k][j] for k in range(3))
                squared_error += (prediction - target) ** 2
            fold_mses.append(squared_error / len(val_indices))

        results.append(sum(fold_mses) / 5)

    return results


def load_original_data_and_check_join():
    features = {}
    with open("/home/user/data/features.csv", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            features[int(row[0])] = [float(x) for x in row[1:4]]

    targets = {}
    with open("/home/user/data/targets.csv", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            targets[int(row[0])] = float(row[1])

    common_ids = sorted(set(features).intersection(targets))
    expected_rows = [[cid] + features[cid] + [targets[cid]] for cid in common_ids]

    assert os.path.isfile(JOINED), f"File {JOINED} does not exist."
    actual_rows = []
    with open(JOINED, newline="") as f:
        for row in csv.reader(f):
            assert len(row) == 5, "joined.csv must contain exactly five comma-separated columns."
            actual_rows.append([float(x) for x in row])

    assert len(actual_rows) == len(expected_rows), "joined.csv does not have the correct number of rows."
    for actual, expected in zip(actual_rows, expected_rows):
        assert actual[0] == expected[0], "joined.csv is not sorted by id or has incorrect ids."
        for a, e in zip(actual, expected):
            assert math.isclose(a, e, rel_tol=1e-5, abs_tol=1e-5), \
                "joined.csv values do not match the expected inner join."

    return [row[1:] for row in expected_rows]


def run_pipeline():
    completed = subprocess.run(
        [BINARY], cwd="/home/user", text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15
    )
    assert completed.returncode == 0, \
        f"pipeline exited with code {completed.returncode}: {completed.stderr}"
    output = completed.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        assert False, f"pipeline stdout must be a single float, got: {output!r}"
    assert math.isfinite(value), "pipeline output must be finite."
    return value


def make_probe_data():
    rows = []
    for i in range(50):
        fold = i // 10
        f1 = 0.31 * i + 7.5 * fold + math.sin(i * 0.37)
        f2 = ((-1) ** i) * (1.0 + 0.08 * i) + 1.9 * fold
        f3 = 1.4 * (i % 7) - 3.2 * fold + math.cos(i * 0.23)
        target = (0.43 * f1 - 0.76 * f2 + 0.18 * f3 +
                  1.6 * math.sin(i * 0.29) + 1.1 * fold)
        rows.append([f1, f2, f3, target])
    return rows


def test_final_state():
    original_dataset = load_original_data_and_check_join()

    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    compilation = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE, "-o", BINARY],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compilation.returncode == 0, f"pipeline.cpp does not compile:\n{compilation.stderr}"

    assert os.path.isfile(FINAL), f"File {FINAL} does not exist."
    with open(FINAL) as f:
        final_text = f.read().strip()
    try:
        final_value = float(final_text)
    except ValueError:
        assert False, f"Could not parse final_mse.txt as a float. Got: {final_text}"

    original_expected = expected_mses(original_dataset)
    assert any(math.isclose(final_value, value, abs_tol=0.1) for value in original_expected), \
        f"Expected MSE around {original_expected[0]:.4f} or {original_expected[1]:.4f}, got {final_value:.4f}."

    original_stdout = run_pipeline()
    assert any(math.isclose(original_stdout, value, abs_tol=0.1) for value in original_expected), \
        "The compiled pipeline does not produce the correct MSE for joined.csv."

    with open(JOINED, "rb") as f:
        joined_backup = f.read()
    final_backup = None
    if os.path.exists(FINAL):
        with open(FINAL, "rb") as f:
            final_backup = f.read()

    probe = make_probe_data()
    try:
        with open(JOINED, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            for i, row in enumerate(probe, 1):
                writer.writerow([i] + [format(x, ".17g") for x in row])

        probe_output = run_pipeline()
        probe_expected = expected_mses(probe)
        assert any(math.isclose(probe_output, value, abs_tol=0.02) for value in probe_expected), \
            f"Pipeline failed the cross-validation probe: got {probe_output}, expected about {probe_expected}."
    finally:
        with open(JOINED, "wb") as f:
            f.write(joined_backup)
        if final_backup is not None:
            with open(FINAL, "wb") as f:
                f.write(final_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
