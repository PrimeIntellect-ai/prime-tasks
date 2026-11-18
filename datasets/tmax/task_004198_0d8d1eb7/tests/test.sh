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

HOME = "/home/user"
DATASET = os.path.join(HOME, "embeddings.csv")
MODEL_C = os.path.join(HOME, "model.c")
MODEL = os.path.join(HOME, "model")
TUNE = os.path.join(HOME, "tune.sh")
BEST = os.path.join(HOME, "best_model.txt")
ALPHAS = [0.1, 0.3, 0.5, 0.7, 0.9]


def expected_accuracy(rows, alpha):
    correct = 0
    for row in rows:
        x1, x2, x3 = float(row[1]), float(row[2]), float(row[3])
        label = int(row[4])
        dist = math.sqrt((x1 - 1.0) ** 2 + (x2 - 1.0) ** 2 + (x3 - 1.0) ** 2)
        pred = 1 if math.exp(-dist) * alpha > 0.1 else 0
        correct += pred == label
    return correct / len(rows)


def expected_best(rows):
    best_alpha = None
    best_acc = -1.0
    for alpha in ALPHAS:
        acc = expected_accuracy(rows, alpha)
        if acc > best_acc or (acc == best_acc and (best_alpha is None or alpha < best_alpha)):
            best_alpha, best_acc = alpha, acc
    return best_alpha, best_acc


def read_rows(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def check_best_file(rows):
    assert os.path.exists(BEST), f"The file {BEST} is missing."
    assert os.path.isfile(BEST), f"{BEST} is not a file."
    content = open(BEST).read().strip()
    parts = content.split(",")
    assert len(parts) == 2, f"Expected format 'alpha,accuracy' in {BEST}, but got '{content}'"
    try:
        student_alpha = float(parts[0].strip())
        student_acc = float(parts[1].strip())
    except ValueError:
        raise AssertionError(f"Could not parse float values from {BEST} content: '{content}'")

    best_alpha, best_acc = expected_best(rows)
    assert math.isclose(student_alpha, best_alpha, rel_tol=1e-5), \
        f"Expected best alpha to be {best_alpha}, but got {student_alpha}."
    expected_rounded = round(best_acc, 2)
    assert (math.isclose(student_acc, expected_rounded, rel_tol=1e-5) or
            math.isclose(student_acc, best_acc, rel_tol=1e-5)), \
        f"Expected accuracy to be {expected_rounded}, but got {student_acc}."


def run_model(binary, csv_path, alpha, rows):
    result = subprocess.run(
        [binary, csv_path, str(alpha)], text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, \
        f"Model failed for alpha {alpha}: {result.stderr or result.stdout}"
    assert result.stderr == "", f"Model printed unexpected stderr: {result.stderr!r}"
    assert re.fullmatch(r"\s*(?:\d+(?:\.\d*)?|\.\d+)\s*", result.stdout), \
        f"Model must print only one floating-point accuracy, got {result.stdout!r}"
    actual = float(result.stdout.strip())
    expected = expected_accuracy(rows, alpha)
    assert math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-6), \
        f"For alpha {alpha}, expected accuracy {expected}, got {actual}"


def make_probe(seed):
    rng = random.Random(seed)
    rows = []
    for i in range(1, 41):
        x1 = round(rng.uniform(-0.5, 2.5), 4)
        x2 = round(rng.uniform(-0.5, 2.5), 4)
        x3 = round(rng.uniform(-0.5, 2.5), 4)
        label = rng.randrange(2)
        rows.append([str(i), str(x1), str(x2), str(x3), str(label)])
    return rows


def write_rows(path, rows):
    with open(path, "w", newline="") as f:
        csv.writer(f).writerows(rows)


def make_hidden_tuning_data():
    rng = random.SystemRandom()
    generating_alpha = rng.choice([0.3, 0.5, 0.7, 0.9])
    rows = []
    for i in range(1, 101):
        x1 = round(rng.uniform(0.0, 2.0), 4)
        x2 = round(rng.uniform(0.0, 2.0), 4)
        x3 = round(rng.uniform(0.0, 2.0), 4)
        dist = math.sqrt((x1 - 1.0) ** 2 + (x2 - 1.0) ** 2 + (x3 - 1.0) ** 2)
        label = 1 if math.exp(-dist) * generating_alpha > 0.1 else 0
        if rng.random() < 0.12:
            label = 1 - label
        rows.append([str(i), str(x1), str(x2), str(x3), str(label)])
    return rows


def main():
    # Preserve all original existence and final-output assertions.
    assert os.path.exists(MODEL_C), f"The file {MODEL_C} is missing."
    assert os.path.isfile(MODEL_C), f"{MODEL_C} is not a file."
    assert os.path.exists(TUNE), f"The file {TUNE} is missing."
    assert os.path.isfile(TUNE), f"{TUNE} is not a file."
    assert os.path.exists(DATASET), f"The file {DATASET} is missing."

    original_rows = read_rows(DATASET)
    check_best_file(original_rows)

    # Compile and exercise the submitted C implementation on independently
    # generated CSV inputs and several alpha values.
    compiled = "/tmp/verified_model"
    build = subprocess.run(
        ["gcc", "-o", compiled, MODEL_C, "-lm"], text=True,
        capture_output=True, timeout=20
    )
    assert build.returncode == 0, f"model.c did not compile: {build.stderr}"
    assert open(compiled, "rb").read(4) == b"\x7fELF", "gcc output is not an ELF executable"

    for seed, alphas in [(7319, [0.1, 0.42, 0.9]), (19411, [0.3, 0.7, 1.2])]:
        rows = make_probe(seed)
        path = f"/tmp/model_probe_{seed}.csv"
        write_rows(path, rows)
        for alpha in alphas:
            run_model(compiled, path, alpha, rows)

    original_dataset = open(DATASET, "rb").read()
    original_best = open(BEST, "rb").read() if os.path.exists(BEST) else None
    try:
        # Replace the primary data only during verification, forcing tune.sh to
        # perform tuning rather than reproduce the known answer.
        hidden_rows = make_hidden_tuning_data()
        write_rows(DATASET, hidden_rows)
        if os.path.lexists(MODEL):
            os.remove(MODEL)
        if os.path.lexists(BEST):
            os.remove(BEST)

        result = subprocess.run(
            ["bash", TUNE], cwd=HOME, text=True, capture_output=True, timeout=40
        )
        assert result.returncode == 0, \
            f"tune.sh failed: {result.stderr or result.stdout}"
        assert os.path.isfile(MODEL), "tune.sh did not create /home/user/model"
        assert os.access(MODEL, os.X_OK), "/home/user/model is not executable"
        assert open(MODEL, "rb").read(4) == b"\x7fELF", \
            "/home/user/model is not a compiled ELF executable"

        check_best_file(hidden_rows)
        run_model(MODEL, DATASET, 0.5, hidden_rows)

        # Ensure the source left after running the script remains compilable and valid.
        after = "/tmp/verified_model_after_tune"
        build = subprocess.run(
            ["gcc", "-o", after, MODEL_C, "-lm"], text=True,
            capture_output=True, timeout=20
        )
        assert build.returncode == 0, f"model.c did not compile after tune.sh: {build.stderr}"
        run_model(after, DATASET, 0.7, hidden_rows)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        if original_best is None:
            if os.path.lexists(BEST):
                os.remove(BEST)
        else:
            with open(BEST, "wb") as f:
                f.write(original_best)


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
