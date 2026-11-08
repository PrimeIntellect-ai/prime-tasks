#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

DATA_DIR = "/home/user/mlops/data"
CSV_OUTPUT = "/home/user/mlops/etl_output.csv"
REPORT_OUTPUT = "/home/user/mlops/report.txt"

def get_expected_data():
    P = [0.5, -0.5, 0.5, -0.5]
    records = []

    for i in range(1, 51):
        filename = f"exp_{i:02d}.json"
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.exists(filepath):
            continue
        with open(filepath, 'r') as f:
            data = json.load(f)

        pw = sum(w * p for w, p in zip(data["weights"], P))
        records.append({
            "id": data["id"],
            "projected_weight": pw,
            "error_rate": data["error_rate"]
        })

    records.sort(key=lambda x: x["error_rate"])

    X = [r["projected_weight"] for r in records]
    Y = [r["error_rate"] for r in records]

    N = len(X)
    sum_x = sum(X)
    sum_y = sum(Y)
    sum_xy = sum(x * y for x, y in zip(X, Y))
    sum_x2 = sum(x**2 for x in X)

    slope = (N * sum_xy - sum_x * sum_y) / (N * sum_x2 - sum_x**2)
    intercept = (sum_y - slope * sum_x) / N

    return records, slope, intercept

def test_etl_csv_output():
    """Test that the ETL CSV output is correctly formatted and sorted."""
    assert os.path.exists(CSV_OUTPUT), f"Expected CSV output file {CSV_OUTPUT} is missing."

    expected_records, _, _ = get_expected_data()
    assert len(expected_records) == 50, "Expected 50 records in the data directory."

    with open(CSV_OUTPUT, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."
    header = rows[0]
    assert header == ["id", "projected_weight", "error_rate"], f"Incorrect CSV header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 50, f"Expected 50 data rows in CSV, found {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_records)):
        assert actual[0] == expected["id"], f"Row {i+1}: expected id {expected['id']}, got {actual[0]}"

        actual_pw = float(actual[1])
        assert math.isclose(actual_pw, expected["projected_weight"], rel_tol=1e-5), \
            f"Row {i+1}: expected projected_weight {expected['projected_weight']}, got {actual_pw}"

        actual_er = float(actual[2])
        assert math.isclose(actual_er, expected["error_rate"], rel_tol=1e-5), \
            f"Row {i+1}: expected error_rate {expected['error_rate']}, got {actual_er}"

def test_regression_report():
    """Test that the regression report contains the correct slope and intercept."""
    assert os.path.exists(REPORT_OUTPUT), f"Expected report file {REPORT_OUTPUT} is missing."

    _, expected_slope, expected_intercept = get_expected_data()

    with open(REPORT_OUTPUT, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "Report file should contain at least two lines for Slope and Intercept."

    slope_line = lines[0]
    intercept_line = lines[1]

    assert slope_line.startswith("Slope: "), "First line must start with 'Slope: '"
    assert intercept_line.startswith("Intercept: "), "Second line must start with 'Intercept: '"

    try:
        actual_slope = float(slope_line.split(":", 1)[1].strip())
    except ValueError:
        pytest.fail("Could not parse numeric value for Slope.")

    try:
        actual_intercept = float(intercept_line.split(":", 1)[1].strip())
    except ValueError:
        pytest.fail("Could not parse numeric value for Intercept.")

    expected_slope_str = f"{expected_slope:.4f}"
    expected_intercept_str = f"{expected_intercept:.4f}"

    assert f"{actual_slope:.4f}" == expected_slope_str, \
        f"Expected Slope {expected_slope_str}, got {actual_slope:.4f}"

    assert f"{actual_intercept:.4f}" == expected_intercept_str, \
        f"Expected Intercept {expected_intercept_str}, got {actual_intercept:.4f}"
TEST_EOF

verify_submission() {
    PROJECT=/home/user/mlops/artifact_tracker
    MANIFEST="$PROJECT/Cargo.toml"

    test -d "$PROJECT" || return 1
    test -f "$MANIFEST" || return 1
    test -f "$PROJECT/src/main.rs" || return 1

    su - user -c 'cargo metadata --manifest-path /home/user/mlops/artifact_tracker/Cargo.toml --no-deps --format-version 1' > /tmp/artifact_tracker_metadata.json || return 1

    python3 - << 'PY' || return 1
import json
import os

project = "/home/user/mlops/artifact_tracker"
manifest = os.path.realpath(os.path.join(project, "Cargo.toml"))
with open("/tmp/artifact_tracker_metadata.json", "r") as f:
    metadata = json.load(f)

packages = [p for p in metadata.get("packages", [])
            if os.path.realpath(p.get("manifest_path", "")) == manifest]
assert len(packages) == 1, "Cargo project package was not found"
package = packages[0]
assert package.get("name") == "artifact_tracker", "Cargo package must be named artifact_tracker"

targets = [t for t in package.get("targets", [])
           if t.get("name") == "artifact_tracker" and "bin" in t.get("kind", [])]
assert targets, "Cargo project must define an artifact_tracker binary target"
for target in targets:
    src = target.get("src_path", "")
    assert src.endswith(".rs") and os.path.isfile(src), "Binary target must have a Rust source file"
PY

    su - user -c 'cd /home/user/mlops/artifact_tracker && cargo build --bin artifact_tracker --message-format=json' > /tmp/artifact_tracker_build.json || return 1

    python3 - << 'PY' > /tmp/artifact_tracker_binary || return 1
import json

executable = None
with open("/tmp/artifact_tracker_build.json", "r") as f:
    for line in f:
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get("target", {})
        if (message.get("reason") == "compiler-artifact"
                and target.get("name") == "artifact_tracker"
                and "bin" in target.get("kind", [])
                and message.get("executable")):
            executable = message["executable"]
assert executable, "Cargo did not produce the artifact_tracker binary"
print(executable)
PY

    BINARY=$(cat /tmp/artifact_tracker_binary) || return 1
    test -f "$BINARY" || return 1
    test -x "$BINARY" || return 1

    rm -f /home/user/mlops/etl_output.csv /home/user/mlops/report.txt || return 1
    (cd "$PROJECT" && "$BINARY") || return 1

    test -f /home/user/mlops/etl_output.csv || return 1
    test -f /home/user/mlops/report.txt || return 1

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if verify_submission 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
