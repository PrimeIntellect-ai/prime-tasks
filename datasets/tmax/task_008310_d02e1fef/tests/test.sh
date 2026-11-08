#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

PROJECT=/home/user/pca_cleaner
SOURCE="$PROJECT/src/main.rs"
BINARY="$PROJECT/target/debug/pca_cleaner"
OUTPUT=/home/user/projected.csv
ok=1

[ -f "$SOURCE" ] && [ -s "$SOURCE" ] || ok=0

if [ "$ok" -eq 1 ]; then
    rm -rf "$PROJECT/target"
    (cd "$PROJECT" && cargo build --quiet) || ok=0
fi

if [ "$ok" -eq 1 ]; then
    [ -x "$BINARY" ] || ok=0
fi

if [ "$ok" -eq 1 ]; then
    python3 - "$BINARY" <<'PY' || ok=0
import os
import sys
path = sys.argv[1]
assert os.path.isfile(path), f"Compiled binary {path} is missing"
with open(path, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"
PY
fi

# Remove any hand-written output and require the compiled Rust program to recreate it.
if [ "$ok" -eq 1 ]; then
    rm -f "$OUTPUT"
    "$BINARY" || ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess
import pytest

INPUT_PATH = "/home/user/data/measurements.csv"
OUTPUT_PATH = "/home/user/projected.csv"
BINARY_PATH = "/home/user/pca_cleaner/target/debug/pca_cleaner"


def test_projected_csv_correctness():
    input_path = "/home/user/data/measurements.csv"
    output_path = "/home/user/projected.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did you run the Rust program?"

    # Read and process the input data to derive the expected truth
    valid_rows = []
    with open(input_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            try:
                id_val = row[0]
                features = [float(x) for x in row[1:]]
                valid_rows.append((id_val, features))
            except ValueError:
                # Skip rows with unparseable floats
                continue

    assert len(valid_rows) > 0, "No valid rows found in the input data."

    # Compute feature means
    num_features = len(valid_rows[0][1])
    means = [0.0] * num_features
    for _, features in valid_rows:
        for i in range(num_features):
            means[i] += features[i]
    for i in range(num_features):
        means[i] /= len(valid_rows)

    # Define the projection matrix from the task
    proj = [
        [0.5, 0.5, -0.5, -0.5],
        [0.5, -0.5, 0.5, -0.5]
    ]

    # Compute the expected projected rows
    expected_output = []
    for id_val, features in valid_rows:
        centered = [features[i] - means[i] for i in range(num_features)]
        p1 = sum(centered[i] * proj[0][i] for i in range(num_features))
        p2 = sum(centered[i] * proj[1][i] for i in range(num_features))
        expected_output.append((id_val, f"{p1:.4f}", f"{p2:.4f}"))

    # Read and validate the actual output
    actual_output = []
    with open(output_path, 'r') as f:
        reader = csv.reader(f)
        try:
            actual_header = next(reader)
        except StopIteration:
            pytest.fail(f"Output file {output_path} is empty.")

        assert actual_header == ["id", "p1", "p2"], f"Output header is incorrect. Expected ['id', 'p1', 'p2'], got {actual_header}"
        for row in reader:
            assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
            actual_output.append((row[0], row[1], row[2]))

    assert len(actual_output) == len(expected_output), f"Output row count mismatch. Expected {len(expected_output)} rows, got {len(actual_output)}"

    for i, (expected, actual) in enumerate(zip(expected_output, actual_output)):
        assert expected == actual, f"Row {i+1} mismatch. Expected {expected}, got {actual}"


def test_compiled_program_handles_unseen_fixture():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    base_id = 10000 + secrets.randbelow(80000)
    valid_rows = []
    for i in range(4):
        features = [secrets.randbelow(81) - 40 for _ in range(4)]
        valid_rows.append((str(base_id + i), features))

    fixture_rows = [
        (valid_rows[0][0], *valid_rows[0][1]),
        (str(base_id + 10), "ERR", 7, 8, 9),
        (valid_rows[1][0], *valid_rows[1][1]),
        (valid_rows[2][0], *valid_rows[2][1]),
        (str(base_id + 11), 1, 2, "N/A", 4),
        (valid_rows[3][0], *valid_rows[3][1]),
    ]

    try:
        with open(INPUT_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "f1", "f2", "f3", "f4"])
            writer.writerows(fixture_rows)

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        subprocess.run([BINARY_PATH], check=True, timeout=30)
        assert os.path.isfile(OUTPUT_PATH), "The compiled Rust program did not create projected.csv"

        means = [sum(row[1][j] for row in valid_rows) / len(valid_rows) for j in range(4)]
        proj = [
            [0.5, 0.5, -0.5, -0.5],
            [0.5, -0.5, 0.5, -0.5],
        ]
        expected = []
        for id_val, features in valid_rows:
            centered = [features[j] - means[j] for j in range(4)]
            p1 = sum(centered[j] * proj[0][j] for j in range(4))
            p2 = sum(centered[j] * proj[1][j] for j in range(4))
            expected.append([id_val, f"{p1:.4f}", f"{p2:.4f}"])

        with open(OUTPUT_PATH, newline="") as f:
            actual = list(csv.reader(f))
        assert actual == [["id", "p1", "p2"], *expected]
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        # Leave the requested output corresponding to the original task fixture.
        subprocess.run([BINARY_PATH], check=True, timeout=30)
TEST_EOF

if [ "$ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
