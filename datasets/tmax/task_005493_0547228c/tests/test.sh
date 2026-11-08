#!/bin/bash
set -e
mkdir -p /logs/verifier

# Force the submitted Rust project to regenerate both artifacts.
rm -f /home/user/convergence.log /home/user/training_data.csv
if ! (cd /home/user/circle_data_gen && timeout 180s cargo run --quiet); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math


def test_project_exists():
    """Ensure the Rust project exists and uses rayon."""
    cargo_toml_path = "/home/user/circle_data_gen/Cargo.toml"
    assert os.path.exists(cargo_toml_path), f"Cargo project file {cargo_toml_path} does not exist."

    with open(cargo_toml_path, "r") as f:
        content = f.read()
        assert "rayon" in content, "rayon dependency not found in Cargo.toml."


def test_convergence_log():
    """Ensure convergence.log has the exact expected lines."""
    log_path = "/home/user/convergence.log"
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "N=10, Area=3.20000",
        "N=20, Area=3.16000",
        "N=40, Area=3.14000",
        "N=80, Area=3.14000"
    ]
    assert lines == expected, f"convergence.log contents do not match expected.\nExpected: {expected}\nGot: {lines}"


def test_training_data_csv():
    """Ensure the CSV contains every distinct center of the converged N=80 grid."""
    csv_path = "/home/user/training_data.csv"
    assert os.path.exists(csv_path), f"{csv_path} does not exist."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, "training_data.csv is empty."

        assert header == ["x", "y", "label"], f"CSV header is incorrect. Expected ['x', 'y', 'label'], got: {header}"

        rows = list(reader)
        expected_rows = 80 * 80
        assert len(rows) == expected_rows, f"CSV should have {expected_rows} data rows, got {len(rows)}."

        # Preserve the original sampled label validation.
        for row in rows[:100] + rows[-100:]:
            assert len(row) == 3, f"Row does not have exactly 3 columns: {row}"
            try:
                x, y, label = float(row[0]), float(row[1]), int(row[2])
            except ValueError:
                assert False, f"Could not parse row values as numbers: {row}"

            expected_label = 1 if (x**2 + y**2) <= 1.0 else 0
            assert label == expected_label, f"Incorrect label for point ({x}, {y}). Expected {expected_label}, got {label}."

        n = 80
        d = 2.0 / n
        tolerance = 1e-9
        seen = set()

        for row_number, row in enumerate(rows, start=2):
            assert len(row) == 3, f"Row {row_number} does not have exactly 3 columns: {row}"
            try:
                x = float(row[0])
                y = float(row[1])
                label = int(row[2])
            except ValueError:
                assert False, f"Could not parse row {row_number} as x,y,label: {row}"

            assert math.isfinite(x) and math.isfinite(y), f"Non-finite coordinate in row {row_number}: {row}"
            assert label in (0, 1), f"Invalid label in row {row_number}: {label}"

            i = round((x + 1.0) / d - 0.5)
            j = round((y + 1.0) / d - 0.5)
            assert 0 <= i < n and 0 <= j < n, f"Point ({x}, {y}) is not an N=80 grid center."

            expected_x = -1.0 + (i + 0.5) * d
            expected_y = -1.0 + (j + 0.5) * d
            assert abs(x - expected_x) <= tolerance and abs(y - expected_y) <= tolerance, \
                f"Point ({x}, {y}) is not the expected center ({expected_x}, {expected_y})."

            key = (i, j)
            assert key not in seen, f"Duplicate grid center ({expected_x}, {expected_y})."
            seen.add(key)

            expected_label = 1 if expected_x**2 + expected_y**2 <= 1.0 else 0
            assert label == expected_label, \
                f"Incorrect label for grid center ({expected_x}, {expected_y}). Expected {expected_label}, got {label}."

        expected_centers = {(i, j) for i in range(n) for j in range(n)}
        assert seen == expected_centers, "CSV does not contain every distinct N=80 grid center exactly once."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
