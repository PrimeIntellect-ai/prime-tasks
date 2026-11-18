#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import pytest

PROJECT = "/home/user/ml_prep"
SOURCE = os.path.join(PROJECT, "src/main.rs")
OUTPUT = os.path.join(PROJECT, "similarity.csv")
USERS = "/home/user/data/users.csv"
FEATURES = "/home/user/data/features.csv"


def run_project():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, \
        f"Rust project failed to run. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def setup_module(module):
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."

    with open(USERS, "w") as f:
        f.write("user_id,name\n1,Alice\n2,Bob\n3,Charlie\n")
    with open(FEATURES, "w") as f:
        f.write("user_id,f1,f2,f3\n1,1.0,,3.0\n2,,2.0,2.0\n3,1.5,1.5,\n")

    run_project()


def test_similarity_csv_exists():
    file_path = "/home/user/ml_prep/similarity.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. Did you run the Rust project?"


def test_similarity_csv_contents():
    file_path = "/home/user/ml_prep/similarity.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 rows in similarity.csv, but found {len(lines)}."

    expected_matrix = [
        [10.0, 6.0, 1.5],
        [6.0, 8.0, 3.0],
        [1.5, 3.0, 4.5]
    ]

    for i, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == 3, f"Row {i+1} does not have exactly 3 columns: '{line}'"

        for j, val_str in enumerate(parts):
            try:
                val = float(val_str)
            except ValueError:
                pytest.fail(f"Could not parse value '{val_str}' as a float at row {i+1}, col {j+1}")

            expected_val = expected_matrix[i][j]
            assert math.isclose(val, expected_val, rel_tol=1e-5, abs_tol=1e-5), \
                f"Value mismatch at row {i+1}, col {j+1}. Expected {expected_val}, got {val}"


def test_project_handles_join_sort_and_runtime_missing_values():
    rng = random.SystemRandom()
    ids = [rng.randint(2, 8), rng.randint(10, 19), rng.randint(30, 59), rng.randint(100, 149)]
    ids.sort()

    def nonzero_half():
        n = 0
        while n == 0:
            n = rng.randint(-18, 18)
        return n / 2.0

    vectors = {
        ids[0]: [nonzero_half(), 0.0, nonzero_half()],
        ids[1]: [0.0, nonzero_half(), nonzero_half()],
        ids[2]: [nonzero_half(), nonzero_half(), 0.0],
        ids[3]: [nonzero_half(), 0.0, nonzero_half()],
    }

    user_rows = [(uid, f"User{uid}") for uid in ids]
    rng.shuffle(user_rows)
    with open(USERS, "w") as f:
        f.write("user_id,name\n")
        for uid, name in user_rows:
            f.write(f"{uid},{name}\n")

    feature_rows = []
    for uid in ids:
        fields = [str(x) if x != 0.0 else "" for x in vectors[uid]]
        feature_rows.append((uid, fields))

    extra_id = 1000 + rng.randint(1, 500)
    feature_rows.append((extra_id, ["99.0", "98.0", "97.0"]))
    rng.shuffle(feature_rows)
    with open(FEATURES, "w") as f:
        f.write("user_id,f1,f2,f3\n")
        for uid, fields in feature_rows:
            f.write(f"{uid},{fields[0]},{fields[1]},{fields[2]}\n")

    expected = []
    for left_id in ids:
        row = []
        for right_id in ids:
            row.append(sum(a * b for a, b in zip(vectors[left_id], vectors[right_id])))
        expected.append(row)

    run_project()
    assert os.path.isfile(OUTPUT), "The executed Rust project did not generate similarity.csv."

    with open(OUTPUT, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == len(ids), \
        f"Expected {len(ids)} joined user rows, found {len(lines)}."
    assert all(line.strip() for line in lines), "similarity.csv contains an empty row."

    for i, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == len(ids), \
            f"Dynamic output row {i+1} has {len(parts)} columns; expected {len(ids)}."
        for j, text in enumerate(parts):
            try:
                actual = float(text)
            except ValueError:
                pytest.fail(f"Dynamic output contains non-numeric value {text!r} at row {i+1}, col {j+1}.")
            assert math.isfinite(actual), \
                f"Dynamic output contains a non-finite value at row {i+1}, col {j+1}."
            assert math.isclose(actual, expected[i][j], rel_tol=1e-9, abs_tol=1e-9), \
                f"Dynamic value mismatch at row {i+1}, col {j+1}: expected {expected[i][j]}, got {actual}."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
