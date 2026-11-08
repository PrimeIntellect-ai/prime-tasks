#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess
import tempfile

PIPELINE = "/home/user/pipeline.go"
EMBEDDINGS = "/home/user/embeddings.csv"
ACCURACY_FILE = "/home/user/fixed_accuracy.txt"
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
OUTPUT_RE = re.compile(r"Accuracy:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)")


def load_data(path):
    data = []
    with open(path, "r", newline="") as f:
        for row in csv.reader(f):
            data.append([float(row[0]), float(row[1]), int(row[2])])
    return data


def evaluate(data, scaling_rows):
    train = data[:80]
    test = data[80:]
    num_features = 2

    means = [sum(row[i] for row in scaling_rows) / len(scaling_rows)
             for i in range(num_features)]
    stds = []
    for i in range(num_features):
        variance = sum((row[i] - means[i]) ** 2 for row in scaling_rows) / len(scaling_rows)
        stds.append(math.sqrt(variance))

    def normalized(row):
        return [((row[i] - means[i]) / stds[i]) if stds[i] != 0 else 0.0
                for i in range(num_features)]

    centroids = {}
    counts = {}
    for row in train:
        label = row[2]
        centroids.setdefault(label, [0.0] * num_features)
        counts[label] = counts.get(label, 0) + 1
        values = normalized(row)
        for i in range(num_features):
            centroids[label][i] += values[i]

    for label in centroids:
        for i in range(num_features):
            centroids[label][i] /= counts[label]

    predictions = []
    for row in test:
        values = normalized(row)
        best_label = None
        best_distance = float("inf")
        for label in sorted(centroids):
            distance = sum((values[i] - centroids[label][i]) ** 2
                           for i in range(num_features))
            if distance < best_distance:
                best_distance = distance
                best_label = label
        predictions.append(best_label)

    correct = sum(pred == row[2] for pred, row in zip(predictions, test))
    return correct / len(test), predictions


def build_pipeline(tmpdir):
    binary = os.path.join(tmpdir, "pipeline")
    result = subprocess.run(
        ["go", "build", "-o", binary, PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, "pipeline.go does not compile:\n" + result.stdout
    return binary


def run_pipeline(binary, workdir):
    result = subprocess.run(
        [binary], cwd=workdir, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, "The repaired pipeline failed:\n" + result.stdout
    matches = OUTPUT_RE.findall(result.stdout)
    assert matches, "The repaired pipeline did not print an 'Accuracy: <number>' result. Output:\n" + result.stdout
    return float(matches[-1])


def write_data(path, data):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(data)


def make_discriminating_case(rng):
    # Create data for which fitting scaling on all 100 rows changes predictions.
    # Labels are then varied so the correct answer cannot be replaced by a
    # constant such as 0 or 1.
    for _ in range(500):
        data = []
        for _ in range(40):
            data.append([rng.gauss(-2.0, 0.45), rng.gauss(-2.0, 0.45), 0])
        for _ in range(40):
            data.append([rng.gauss(2.0, 0.45), rng.gauss(2.0, 0.45), 1])
        for _ in range(20):
            sign = rng.choice([-1.0, 1.0])
            x = sign * rng.uniform(9.0, 35.0)
            y = -sign * rng.uniform(1.0, 4.5) + rng.gauss(0.0, 0.15)
            data.append([x, y, 0])

        _, train_predictions = evaluate(data, data[:80])
        _, leaky_predictions = evaluate(data, data)
        if sum(a != b for a, b in zip(train_predictions, leaky_predictions)) < 5:
            continue

        desired_correct = rng.randint(5, 15)
        matching = set(rng.sample(range(20), desired_correct))
        for i in range(20):
            prediction = train_predictions[i]
            data[80 + i][2] = prediction if i in matching else 1 - prediction

        correct_accuracy, _ = evaluate(data, data[:80])
        leaky_accuracy, _ = evaluate(data, data)
        if not math.isclose(correct_accuracy, leaky_accuracy, abs_tol=1e-12):
            return data, correct_accuracy
    raise AssertionError("Could not generate a discriminating evaluation dataset")


def test_fixed_pipeline_and_accuracy_file():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    assert os.path.isfile(ACCURACY_FILE), f"{ACCURACY_FILE} is missing. Did you save the accuracy?"
    assert os.path.isfile(EMBEDDINGS), f"{EMBEDDINGS} is missing."

    original_data = load_data(EMBEDDINGS)
    assert len(original_data) == 100, "Expected exactly 100 rows in embeddings.csv"
    expected_accuracy, _ = evaluate(original_data, original_data[:80])

    with open(ACCURACY_FILE, "r") as f:
        content = f.read().strip()
    assert NUMBER_RE.fullmatch(content), \
        f"File {ACCURACY_FILE} does not contain only a valid decimal number. Content found: '{content}'"
    actual_accuracy = float(content)
    assert math.isclose(actual_accuracy, expected_accuracy, rel_tol=1e-4, abs_tol=1e-4), \
        f"Incorrect saved accuracy. Expected {expected_accuracy:.6f}, got {actual_accuracy:.6f}."

    with tempfile.TemporaryDirectory() as build_dir:
        binary = build_pipeline(build_dir)

        # The program itself must produce the correct result on the supplied data.
        program_accuracy = run_pipeline(binary, "/home/user")
        assert math.isclose(program_accuracy, expected_accuracy, rel_tol=1e-6, abs_tol=1e-6), \
            f"pipeline.go produced {program_accuracy:.6f}; expected {expected_accuracy:.6f}."

        # Exercise the implementation on fresh cases that distinguish training-only
        # scaling from fitting the scaler before the split.
        rng = random.SystemRandom()
        for case_number in range(3):
            case_data, case_expected = make_discriminating_case(rng)
            with tempfile.TemporaryDirectory() as case_dir:
                write_data(os.path.join(case_dir, "embeddings.csv"), case_data)
                case_actual = run_pipeline(binary, case_dir)
            assert math.isclose(case_actual, case_expected, rel_tol=1e-6, abs_tol=1e-6), \
                (f"pipeline.go failed generated case {case_number + 1}: expected "
                 f"{case_expected:.6f}, got {case_actual:.6f}. Ensure the split occurs "
                 "before scaling and only training statistics are used.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
