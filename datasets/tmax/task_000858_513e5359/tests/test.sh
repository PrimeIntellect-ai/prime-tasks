#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import subprocess

TRAIN = "/home/user/train_data.csv"
PROJECT = "/home/user/ml_pipeline"
PREDICTIONS = "/home/user/predictions.txt"
TEST_FEATURES = "/app/test_features.csv"


def read_predictions(path, expected_count):
    assert os.path.exists(path), f"Missing predictions file at {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert len(lines) == expected_count, (
        f"Length mismatch: predicted {len(lines)} values, expected {expected_count}"
    )
    values = []
    for i, line in enumerate(lines, 1):
        assert line.strip(), f"Prediction line {i} is blank"
        assert len(line.split()) == 1, f"Prediction line {i} is not a single value"
        try:
            value = float(line)
        except ValueError as e:
            raise AssertionError(f"Invalid prediction on line {i}: {line!r}") from e
        assert math.isfinite(value), f"Prediction line {i} is not finite"
        values.append(value)
    return values


def run_pipeline():
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
        check=False,
    )
    assert result.returncode == 0, f"Rust pipeline failed:\n{result.stdout}"
    mse_lines = [line for line in result.stdout.splitlines()
                 if re.search(r"(?i)mean", line) and re.search(r"(?i)mse", line)]
    assert mse_lines, (
        "Rust pipeline did not print a mean validation MSE; output was:\n" + result.stdout
    )
    assert any(re.search(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", line)
               for line in mse_lines), "Mean validation MSE output has no numeric value"
    return result.stdout


def validate_training_csv():
    assert os.path.exists(TRAIN), f"Missing parsed training data at {TRAIN}"
    assert os.path.isfile(TRAIN), f"{TRAIN} is not a file"

    with open(TRAIN, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        rows = list(reader)
    assert rows, "train_data.csv is empty"
    assert rows[0] == ["feature_a", "feature_b", "target"], (
        f"Incorrect CSV header: {rows[0]!r}"
    )
    assert len(rows) == 51, f"Expected 50 dictated rows, found {len(rows) - 1}"

    rng = random.Random(42)
    expected = []
    for _ in range(50):
        fa = round(rng.uniform(-2.0, 5.0), 1)
        fb = round(rng.uniform(-2.0, 5.0), 1)
        target = round(3.5 * fa - 1.2 * fb + 4.0 + rng.gauss(0, 0.5), 1)
        expected.append((fa, fb, target))

    for row_number, (row, wanted) in enumerate(zip(rows[1:], expected), 1):
        assert len(row) == 3, f"Training row {row_number} does not have three columns"
        try:
            actual = tuple(float(x) for x in row)
        except ValueError as e:
            raise AssertionError(f"Non-numeric training row {row_number}: {row!r}") from e
        assert all(math.isfinite(x) for x in actual), f"Non-finite training row {row_number}"
        assert all(abs(a - b) < 1e-9 for a, b in zip(actual, wanted)), (
            f"Training row {row_number} does not match the dictated audio: "
            f"got {actual}, expected {wanted}"
        )


def validate_rust_project():
    assert os.path.exists(PROJECT), f"Missing Rust project directory at {PROJECT}"
    assert os.path.isdir(PROJECT), f"{PROJECT} is not a directory"
    manifest = os.path.join(PROJECT, "Cargo.toml")
    main_rs = os.path.join(PROJECT, "src", "main.rs")
    assert os.path.isfile(manifest), "Rust project is missing Cargo.toml"
    assert os.path.isfile(main_rs), "Rust project is missing src/main.rs"

    with open(manifest, encoding="utf-8") as f:
        cargo = f.read().lower()
    with open(main_rs, encoding="utf-8") as f:
        source = f.read()
    lower = source.lower()

    libraries = ("smartcore", "linfa", "rusty-machine", "rusty_machine")
    assert any(lib in cargo for lib in libraries), (
        "Cargo.toml does not declare a Rust machine-learning library"
    )
    assert any(lib.replace("-", "_") in lower for lib in libraries), (
        "Rust source does not use the declared machine-learning library"
    )
    assert re.search(r"(?i)linear.?regression", source), (
        "Rust source does not implement linear regression"
    )
    assert "fold" in lower, "Rust source does not contain k-fold cross-validation logic"
    assert re.search(r"(?i)(?:k|folds?|n_splits)\s*[:=,(][^\n;]{0,30}\b3\b|with_n_splits\s*\(\s*3\s*\)", source), (
        "Rust source does not configure 3-fold cross-validation"
    )
    assert "mse" in lower or "mean_squared_error" in lower, (
        "Rust source does not calculate/report validation MSE"
    )
    for required in ("train_data.csv", "test_features.csv", "predictions.txt"):
        assert required in source, f"Rust source does not reference {required}"


def main():
    validate_training_csv()
    validate_rust_project()

    # Execute the submitted Rust application on the required files rather than
    # trusting a pre-created predictions file.
    run_pipeline()
    preds = read_predictions(PREDICTIONS, 5)
    targets = [6.3, 12.75, -1.9, 19.2, 4.0]
    mse = sum((p - t) ** 2 for p, t in zip(preds, targets)) / len(targets)
    assert mse <= 2.0, f"MSE too high: {mse} (must be <= 2.0)"

    # Replace both datasets with an unpredictable exact linear problem and run
    # the Rust artifact again. This rejects fixed prediction files and programs
    # that do not actually read, train, and infer from the requested inputs.
    with open(TRAIN, "rb") as f:
        original_train = f.read()
    with open(TEST_FEATURES, "rb") as f:
        original_test = f.read()
    with open(PREDICTIONS, "rb") as f:
        original_predictions = f.read()

    sysrng = secrets.SystemRandom()
    b0 = sysrng.uniform(-20.0, 20.0)
    b1 = sysrng.uniform(1.5, 7.0) * sysrng.choice([-1.0, 1.0])
    b2 = sysrng.uniform(1.5, 7.0) * sysrng.choice([-1.0, 1.0])
    train_rows = []
    for _ in range(18):
        a = sysrng.uniform(-8.0, 8.0)
        b = sysrng.uniform(-8.0, 8.0)
        train_rows.append((a, b, b0 + b1 * a + b2 * b))
    test_rows = [(sysrng.uniform(-7.0, 7.0), sysrng.uniform(-7.0, 7.0))
                 for _ in range(7)]
    expected = [b0 + b1 * a + b2 * b for a, b in test_rows]

    try:
        with open(TRAIN, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["feature_a", "feature_b", "target"])
            writer.writerows((f"{a:.12f}", f"{b:.12f}", f"{y:.12f}")
                             for a, b, y in train_rows)
        with open(TEST_FEATURES, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["feature_a", "feature_b"])
            writer.writerows((f"{a:.12f}", f"{b:.12f}") for a, b in test_rows)
        if os.path.exists(PREDICTIONS):
            os.remove(PREDICTIONS)

        run_pipeline()
        dynamic_preds = read_predictions(PREDICTIONS, len(expected))
        dynamic_mse = sum((p - y) ** 2 for p, y in zip(dynamic_preds, expected)) / len(expected)
        max_error = max(abs(p - y) for p, y in zip(dynamic_preds, expected))
        assert dynamic_mse <= 1e-4 and max_error <= 0.02, (
            "Rust pipeline failed the hidden linear-regression inference test: "
            f"MSE={dynamic_mse}, max error={max_error}"
        )
    finally:
        with open(TRAIN, "wb") as f:
            f.write(original_train)
        with open(TEST_FEATURES, "wb") as f:
            f.write(original_test)
        with open(PREDICTIONS, "wb") as f:
            f.write(original_predictions)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
