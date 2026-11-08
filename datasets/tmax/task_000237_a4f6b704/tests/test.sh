#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

PROJECT = "/home/user/dataset_organizer"
CSV_PATH = os.path.join(PROJECT, "data/embeddings.csv")
SOURCE_PATH = os.path.join(PROJECT, "src/main.rs")
RESULT_PATH = os.path.join(PROJECT, "test_sum.txt")
BINARY_PATH = "/tmp/dataset_organizer_verified_bin"


def expected_output(data):
    train_set = data[:80]
    test_set = data[80:]
    num_cols = len(data[0])

    train_means = [0.0] * num_cols
    for row in train_set:
        for j in range(num_cols):
            train_means[j] += row[j]
    for j in range(num_cols):
        train_means[j] /= len(train_set)

    expected_sum = 0.0
    for row in test_set:
        for j in range(num_cols):
            expected_sum += row[j] - train_means[j]

    return f"Test sum: {expected_sum:.4f}"


def run_program():
    result = subprocess.run(
        [BINARY_PATH],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout.strip()


def write_csv(data):
    with open(CSV_PATH, "w") as f:
        for row in data:
            f.write(",".join(str(value) for value in row) + "\n")


def random_dataset(trial):
    data = []
    for i in range(100):
        row = []
        for j in range(5):
            if i < 80:
                value = secrets.randbelow(801) - 400 + trial * (j + 1)
            else:
                value = secrets.randbelow(1001) + 700 + trial * 37 - j * 11
            row.append(value)
        data.append(row)
    return data


def test_final_state_and_rust_implementation():
    # Preserve the original verifier's checks of the supplied data and output file.
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} is missing."
    with open(CSV_PATH, "r") as f:
        data = [[float(x) for x in line.strip().split(",")] for line in f if line.strip()]

    assert len(data) == 100, f"Expected 100 rows in CSV, found {len(data)}."
    original_expected = expected_output(data)

    assert os.path.isfile(RESULT_PATH), (
        f"Output file {RESULT_PATH} is missing. Did you save the output?"
    )
    with open(RESULT_PATH, "r") as f:
        actual_output = f.read().strip()
    assert actual_output == original_expected, (
        f"Expected output to be '{original_expected}', but found '{actual_output}'."
    )

    # Compile src/main.rs itself, rather than trusting a prebuilt artifact or output file.
    assert os.path.isfile(SOURCE_PATH), f"Rust source file {SOURCE_PATH} is missing."
    compile_result = subprocess.run(
        ["rustc", "--edition=2021", SOURCE_PATH, "-o", BINARY_PATH],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"src/main.rs did not compile.\nstderr:\n{compile_result.stderr}"
    )

    # The compiled program must produce the saved answer on the original dataset.
    assert run_program() == original_expected, (
        "The compiled src/main.rs does not produce the expected output on the original dataset."
    )

    # Exercise the implementation on unpredictable datasets so a fixed answer cannot pass.
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    try:
        for trial in range(2):
            trial_data = random_dataset(trial)
            write_csv(trial_data)
            expected = expected_output([[float(x) for x in row] for row in trial_data])
            actual = run_program()
            assert re.fullmatch(r"Test sum: -?\d+\.\d{4}", actual), (
                f"Program output has the wrong format: {actual!r}"
            )
            assert actual == expected, (
                f"Program used incorrect centering on a verification dataset: "
                f"expected '{expected}', found '{actual}'."
            )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
