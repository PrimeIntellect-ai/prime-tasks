#!/bin/bash
set +e
mkdir -p /logs/verifier

ORIGINAL_DATA=/tmp/verifier_original_data.csv
cp /home/user/data.csv "$ORIGINAL_DATA"

restore_data() {
    cp "$ORIGINAL_DATA" /home/user/data.csv 2>/dev/null || true
}
trap restore_data EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_rust_project_exists():
    assert os.path.isdir("/home/user/etl_rust"), "Rust project directory /home/user/etl_rust is missing."
    assert os.path.exists("/home/user/etl_rust/Cargo.toml"), "Cargo.toml is missing in /home/user/etl_rust."

def test_selected_features_output():
    output_path = "/home/user/selected_features.csv"
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    with open(output_path, "r", newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output CSV is empty."

    header = rows[0]
    assert len(header) == 2, f"Expected 2 columns in output, found {len(header)}."

    # Check that columns are f2 and f5
    assert set(header) == {"f2", "f5"}, f"Expected columns 'f2' and 'f5', found {header}."

    # Determine indices
    f2_idx = header.index("f2")
    f5_idx = header.index("f5")

    expected_f2 = ["100", "110", "120", "110", "130", "105"]
    expected_f5 = ["5000", "5500", "5100", "5200", "5100", "5000"]

    data_rows = rows[1:]
    assert len(data_rows) == 6, f"Expected 6 data rows, found {len(data_rows)}."

    actual_f2 = [row[f2_idx] for row in data_rows]
    actual_f5 = [row[f5_idx] for row in data_rows]

    assert actual_f2 == expected_f2, f"Column f2 values are incorrect. Expected {expected_f2}, got {actual_f2}."
    assert actual_f5 == expected_f5, f"Column f5 values are incorrect. Expected {expected_f5}, got {actual_f5}."
TEST_EOF

cat << 'PY_EOF' > /tmp/dynamic_etl_test.py
import csv
import json
import os
import random
import sys

HEADERS = ["f1", "f2", "f3", "f4", "f5"]


def median_floor(values):
    values = sorted(values)
    n = len(values)
    if n % 2:
        return values[n // 2]
    return (values[n // 2 - 1] + values[n // 2]) // 2


def expected_for(rows):
    cleaned_columns = {}
    scores = {}
    for col, name in enumerate(HEADERS):
        present = [row[col] for row in rows if row[col] is not None]
        median = median_floor(present)
        cleaned = [median if row[col] is None else row[col] for row in rows]
        cleaned_columns[name] = cleaned
        # For equal-length columns this integer numerator has the same ordering
        # as population variance, without relying on floating-point arithmetic.
        scores[name] = len(cleaned) * sum(v * v for v in cleaned) - sum(cleaned) ** 2
    selected = sorted(HEADERS, key=lambda name: scores[name], reverse=True)[:2]
    return selected, cleaned_columns, scores


def generate(case_number, expected_path):
    rng = random.SystemRandom()
    scales = [5, 31, 173, 911, 5003]
    bases = [10, 100, 1000, 10000, 100000]

    while True:
        rows = []
        for r in range(9):
            row = []
            for c in range(5):
                value = bases[c] + rng.randrange(0, scales[c] + 1) + r * (c + 1)
                row.append(value)
            rows.append(row)

        for c in range(5):
            missing_count = 1 + ((case_number + c) % 3)
            for r in rng.sample(range(len(rows)), missing_count):
                rows[r][c] = None

        selected, cleaned, scores = expected_for(rows)
        if len(set(scores.values())) == 5:
            break

    with open("/home/user/data.csv", "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(HEADERS)
        writer.writerows([["" if value is None else value for value in row] for row in rows])

    with open(expected_path, "w") as f:
        json.dump({"selected": selected, "cleaned": cleaned, "row_count": len(rows)}, f)


def validate(expected_path):
    with open(expected_path) as f:
        expected = json.load(f)
    with open("/home/user/selected_features.csv", newline="") as f:
        rows = list(csv.reader(f))

    assert rows, "Output CSV is empty on a generated input"
    header = rows[0]
    assert len(header) == 2, f"Expected exactly two output columns, got {header}"
    assert len(set(header)) == 2, f"Output header contains duplicate columns: {header}"
    assert set(header) == set(expected["selected"]), (
        f"Wrong features for generated input: expected {expected['selected']}, got {header}"
    )
    data = rows[1:]
    assert len(data) == expected["row_count"], (
        f"Expected {expected['row_count']} rows, got {len(data)}"
    )
    assert all(len(row) == 2 for row in data), "Generated output has malformed rows"
    for index, name in enumerate(header):
        actual = [row[index] for row in data]
        wanted = [str(value) for value in expected["cleaned"][name]]
        assert actual == wanted, f"Incorrect imputed values for {name}: expected {wanted}, got {actual}"


if __name__ == "__main__":
    if sys.argv[1] == "generate":
        generate(int(sys.argv[2]), sys.argv[3])
    elif sys.argv[1] == "validate":
        validate(sys.argv[2])
    else:
        raise SystemExit("unknown mode")
PY_EOF

run_program() {
    rm -f /home/user/selected_features.csv
    (cd /home/user/etl_rust && timeout 180s cargo run --quiet --manifest-path /home/user/etl_rust/Cargo.toml)
    status=$?
    [ "$status" -eq 0 ] || return 1
    [ -f /home/user/selected_features.csv ] || return 1
}

verify_all() {
    [ -d /home/user/etl_rust ] || return 1
    [ -f /home/user/etl_rust/Cargo.toml ] || return 1
    find /home/user/etl_rust/src -type f -name '*.rs' -size +0c -print -quit 2>/dev/null | grep -q . || return 1

    cp "$ORIGINAL_DATA" /home/user/data.csv || return 1
    run_program || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    for case_number in 1 2 3; do
        expected="/tmp/generated_expected_${case_number}.json"
        python3 /tmp/dynamic_etl_test.py generate "$case_number" "$expected" || return 1
        run_program || return 1
        python3 /tmp/dynamic_etl_test.py validate "$expected" || return 1
    done

    # Restore the instructed dataset and verify that executing the program still
    # recreates the originally required final artifact.
    cp "$ORIGINAL_DATA" /home/user/data.csv || return 1
    run_program || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if verify_all 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

restore_data
trap - EXIT
