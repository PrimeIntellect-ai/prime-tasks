#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import random
import re
import subprocess

import numpy as np
import pytest

HOME = "/home/user"
NORMALIZE = os.path.join(HOME, "normalize.sh")
EMBEDDINGS = os.path.join(HOME, "embeddings.csv")
TRAIN = os.path.join(HOME, "train.csv")
TEST = os.path.join(HOME, "test.csv")
LOG_PROBS = os.path.join(HOME, "test_log_probs.txt")


def remove_outputs():
    for path in (TRAIN, TEST, LOG_PROBS, os.path.join(HOME, "normalized.csv")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_command(command):
    return subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def read_nonempty(path):
    with open(path, "r") as f:
        return [line for line in f if line.strip()]


def test_normalize_script_executes_correctly_on_unseen_data():
    assert os.path.isfile(NORMALIZE), "normalize.sh is missing."
    assert os.access(NORMALIZE, os.X_OK), "normalize.sh is not executable."

    with open(EMBEDDINGS, "rb") as f:
        original_embeddings = f.read()

    rng = random.SystemRandom()
    lows = [rng.uniform(-30, 10) for _ in range(3)]
    highs = [low + rng.uniform(8, 25) for low in lows]
    rows = []
    for i in range(100):
        features = []
        for j in range(3):
            low, high = lows[j], highs[j]
            if i == 0:
                value = low
            elif i == 1:
                value = high
            elif i < 80:
                value = rng.uniform(low + 0.1 * (high - low), high - 0.1 * (high - low))
            elif i % 2 == 0:
                value = low - rng.uniform(1, 8)
            else:
                value = high + rng.uniform(1, 8)
            features.append(float(f"{value:.4f}"))
        rows.append(features + [rng.randrange(2)])

    challenge = "".join(
        f"{row[0]:.4f},{row[1]:.4f},{row[2]:.4f},{row[3]}\n" for row in rows
    )

    challenge_error = None
    final_normalize = None
    final_evaluate = None
    try:
        with open(EMBEDDINGS, "w") as f:
            f.write(challenge)
        remove_outputs()

        result = run_command([NORMALIZE])
        assert result.returncode == 0, (
            "normalize.sh failed on an unseen valid embeddings.csv.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(TRAIN), "normalize.sh did not create train.csv."
        assert os.path.isfile(TEST), "normalize.sh did not create test.csv."

        actual_train = read_nonempty(TRAIN)
        actual_test = read_nonempty(TEST)
        assert len(actual_train) == 80, "normalize.sh must create 80 training rows."
        assert len(actual_test) == 20, "normalize.sh must create 20 testing rows."

        mins = [min(row[j] for row in rows[:80]) for j in range(3)]
        maxs = [max(row[j] for row in rows[:80]) for j in range(3)]
        number = r"-?(?:\d+)\.\d{4}"
        row_pattern = re.compile(rf"^{number},{number},{number},[01]$")

        for i, line in enumerate(actual_train + actual_test):
            stripped = line.strip()
            assert row_pattern.fullmatch(stripped), (
                f"normalize.sh output row {i + 1} is not formatted to exactly 4 decimal places: {stripped}"
            )
            parts = stripped.split(",")
            expected = [
                (rows[i][j] - mins[j]) / (maxs[j] - mins[j]) for j in range(3)
            ]
            for j in range(3):
                assert abs(float(parts[j]) - expected[j]) <= 0.000051, (
                    f"normalize.sh produced an incorrect value for unseen row {i + 1}, feature {j + 1}. "
                    "Minima and maxima must come only from the first 80 rows."
                )
            assert int(parts[3]) == rows[i][3], f"Target changed on unseen row {i + 1}."
    except BaseException as exc:
        challenge_error = exc
    finally:
        with open(EMBEDDINGS, "wb") as f:
            f.write(original_embeddings)
        remove_outputs()
        final_normalize = run_command([NORMALIZE])
        if final_normalize.returncode == 0:
            final_evaluate = run_command(["python3", "/home/user/evaluate.py"])

    if challenge_error is not None:
        raise challenge_error
    assert final_normalize.returncode == 0, (
        "normalize.sh failed on the provided embeddings.csv.\n"
        f"stdout:\n{final_normalize.stdout}\nstderr:\n{final_normalize.stderr}"
    )
    assert final_evaluate is not None and final_evaluate.returncode == 0, (
        "python3 /home/user/evaluate.py failed after normalize.sh ran.\n"
        + ("" if final_evaluate is None else f"stdout:\n{final_evaluate.stdout}\nstderr:\n{final_evaluate.stderr}")
    )


def test_output_files_exist():
    assert os.path.isfile("/home/user/train.csv"), "train.csv was not created."
    assert os.path.isfile("/home/user/test.csv"), "test.csv was not created."
    assert os.path.isfile("/home/user/test_log_probs.txt"), "test_log_probs.txt was not created."


def expected_normalized_data():
    data = []
    with open(EMBEDDINGS, "r") as f:
        for line in f:
            if line.strip():
                parts = line.strip().split(",")
                data.append([float(parts[0]), float(parts[1]), float(parts[2]), int(parts[3])])

    assert len(data) == 100, "embeddings.csv should have 100 rows."
    train_data = data[:80]
    mins = [min(row[i] for row in train_data) for i in range(3)]
    maxs = [max(row[i] for row in train_data) for i in range(3)]

    normalized = []
    for row in data:
        values = [(row[i] - mins[i]) / (maxs[i] - mins[i]) for i in range(3)]
        normalized.append([float(f"{values[0]:.4f}"), float(f"{values[1]:.4f}"), float(f"{values[2]:.4f}"), row[3]])
    return data, normalized


def test_correct_normalization_and_split():
    assert os.path.isfile(EMBEDDINGS), "embeddings.csv is missing."
    data, normalized = expected_normalized_data()

    expected_train = [
        f"{row[0]:.4f},{row[1]:.4f},{row[2]:.4f},{row[3]}\n" for row in normalized[:80]
    ]
    expected_test = [
        f"{row[0]:.4f},{row[1]:.4f},{row[2]:.4f},{row[3]}\n" for row in normalized[80:]
    ]

    actual_train = read_nonempty(TRAIN)
    actual_test = read_nonempty(TEST)

    assert len(actual_train) == 80, f"train.csv should have exactly 80 rows, found {len(actual_train)}."
    assert len(actual_test) == 20, f"test.csv should have exactly 20 rows, found {len(actual_test)}."

    for i in range(80):
        assert actual_train[i] == expected_train[i], (
            f"train.csv row {i+1} is incorrect.\n"
            f"Expected: {expected_train[i].strip()}\n"
            f"Got:      {actual_train[i].strip()}\n"
            "Ensure min/max are calculated ONLY from the first 80 rows."
        )

    for i in range(20):
        assert actual_test[i] == expected_test[i], (
            f"test.csv row {i+1} is incorrect.\n"
            f"Expected: {expected_test[i].strip()}\n"
            f"Got:      {actual_test[i].strip()}\n"
            "Ensure min/max are calculated ONLY from the first 80 rows and applied to all 100 rows."
        )


def test_log_probs_output():
    assert os.path.isfile(LOG_PROBS), "test_log_probs.txt is missing."
    lines = read_nonempty(LOG_PROBS)
    assert len(lines) == 20, f"test_log_probs.txt should have 20 rows, found {len(lines)}."

    for i, line in enumerate(lines):
        parts = line.strip().split(",")
        assert len(parts) == 2, f"test_log_probs.txt row {i+1} should have 2 columns (log-probs for class 0 and 1)."
        try:
            float(parts[0])
            float(parts[1])
        except ValueError:
            pytest.fail(f"test_log_probs.txt row {i+1} contains non-numeric values: {line.strip()}")

    _, normalized = expected_normalized_data()
    train = np.asarray(normalized[:80], dtype=float)
    test = np.asarray(normalized[80:], dtype=float)
    X_train, y_train = train[:, :3], train[:, 3]
    X_test = test[:, :3]

    means = {}
    variances = {}
    priors = {}
    for c in [0, 1]:
        X_c = X_train[y_train == c]
        means[c] = np.mean(X_c, axis=0)
        variances[c] = np.var(X_c, axis=0) + 1e-9
        priors[c] = len(X_c) / len(X_train)

    expected = []
    for x in X_test:
        row = []
        for c in [0, 1]:
            ll = -0.5 * np.sum(np.log(2 * np.pi * variances[c])) - 0.5 * np.sum(((x - means[c]) ** 2) / variances[c])
            row.append(ll + np.log(priors[c]))
        expected.append(row)

    expected_buffer = io.StringIO()
    np.savetxt(expected_buffer, np.asarray(expected), fmt="%.4f", delimiter=",")
    expected_lines = expected_buffer.getvalue().splitlines()
    actual_lines = [line.strip() for line in lines]
    assert actual_lines == expected_lines, (
        "test_log_probs.txt does not contain the Gaussian Naive Bayes log-probabilities "
        "produced from the required normalized train and test data."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
