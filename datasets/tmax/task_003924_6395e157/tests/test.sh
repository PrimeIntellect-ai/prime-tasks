#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/evaluate_knn.c"
FEATURES = "/home/user/features.csv"
LABELS = "/home/user/labels.csv"
OUTPUT = "/home/user/best_model.txt"
ORIGINAL_EXPECTED = "Best k: 7, Accuracy: 84.00%"


def read_output():
    assert os.path.isfile(OUTPUT), f"Missing required output file: {OUTPUT}"
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def test_evaluate_knn_c_exists():
    assert os.path.isfile(SOURCE), f"Missing required C source file: {SOURCE}"

    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original basic source check.
    assert "main" in content or "#include" in content, \
        f"{SOURCE} does not appear to be a valid C source file."


def test_best_model_txt_correct():
    content = read_output()
    assert content == ORIGINAL_EXPECTED, \
        f"Incorrect content in {OUTPUT}. Expected '{ORIGINAL_EXPECTED}', but got '{content}'"


def expected_result(features, labels):
    ks = (1, 3, 5, 7)
    correct = {k: 0 for k in ks}

    for held_out in range(1, 101):
        distances = []
        x = features[held_out]
        for other in range(1, 101):
            if other == held_out:
                continue
            z = features[other]
            d2 = sum((x[j] - z[j]) ** 2 for j in range(3))
            distances.append((d2, other))
        distances.sort()

        for k in ks:
            ones = sum(labels[record_id] for _, record_id in distances[:k])
            prediction = 1 if ones > k // 2 else 0
            if prediction == labels[held_out]:
                correct[k] += 1

    best_k = ks[0]
    for k in ks[1:]:
        if correct[k] > correct[best_k]:
            best_k = k
    return f"Best k: {best_k}, Accuracy: {correct[best_k]:.2f}%"


def write_dataset(features, labels, rng):
    feature_ids = list(range(1, 101))
    label_ids = list(range(1, 101))
    rng.shuffle(feature_ids)
    rng.shuffle(label_ids)

    with open(FEATURES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "f1", "f2", "f3"])
        for record_id in feature_ids:
            writer.writerow([record_id] + [format(v, ".17g") for v in features[record_id]])

    with open(LABELS, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "label"])
        for record_id in label_ids:
            writer.writerow([record_id, labels[record_id]])


def run_program(executable):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [executable], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, \
        f"Compiled program exited with status {result.returncode}. stderr: {result.stderr}"
    return read_output()


def test_compile_run_join_and_knn_behavior():
    with open(FEATURES, "rb") as f:
        original_features = f.read()
    with open(LABELS, "rb") as f:
        original_labels = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    fd, executable = tempfile.mkstemp(prefix="evaluate_knn_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)

    try:
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", executable, "-lm"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert compile_result.returncode == 0, \
            f"Failed to compile {SOURCE}: {compile_result.stderr}"

        # Delete the submitted output and require the compiled artifact to recreate it.
        actual = run_program(executable)
        assert actual == ORIGINAL_EXPECTED, \
            f"Program produced '{actual}' on the supplied data; expected '{ORIGINAL_EXPECTED}'"

        # Exercise independently shuffled, unpredictable datasets. Expected answers
        # are derived here from the CSV semantics rather than trusted constants.
        seed = secrets.randbits(64)
        rng = random.Random(seed)
        for trial, separation in enumerate((0.7, 1.3, 2.1, 3.0)):
            label_values = [0] * 50 + [1] * 50
            rng.shuffle(label_values)
            labels = {record_id: label_values[record_id - 1] for record_id in range(1, 101)}
            features = {}
            for record_id in range(1, 101):
                center = separation if labels[record_id] else -separation
                features[record_id] = (
                    center + rng.gauss(0.0, 2.4),
                    0.65 * center + rng.gauss(0.0, 2.4),
                    -0.35 * center + rng.gauss(0.0, 2.4),
                )

            expected = expected_result(features, labels)
            write_dataset(features, labels, rng)
            actual = run_program(executable)
            assert actual == expected, \
                f"Trial {trial} (seed {seed}) produced '{actual}', expected '{expected}'"
    finally:
        with open(FEATURES, "wb") as f:
            f.write(original_features)
        with open(LABELS, "wb") as f:
            f.write(original_labels)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
        if os.path.exists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
