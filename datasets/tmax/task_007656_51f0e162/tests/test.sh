#!/bin/bash
mkdir -p /logs/verifier

build_ok=1

if [ ! -f /home/user/pipeline/src/main.rs ] || [ -L /home/user/pipeline/src/main.rs ]; then
    build_ok=0
fi

if [ "$build_ok" -eq 1 ]; then
    cd /home/user/pipeline || build_ok=0
fi

if [ "$build_ok" -eq 1 ]; then
    cargo clean >/tmp/pipeline_cargo_clean.log 2>&1 || build_ok=0
fi

if [ "$build_ok" -eq 1 ]; then
    cargo build --release >/tmp/pipeline_cargo_build.log 2>&1 || build_ok=0
fi

if [ "$build_ok" -eq 1 ] && { [ ! -f /home/user/pipeline/target/release/pipeline ] || [ ! -x /home/user/pipeline/target/release/pipeline ]; }; then
    build_ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import random
import subprocess
import pytest

SOURCE = "/home/user/pipeline/src/main.rs"
BINARY = "/home/user/pipeline/target/release/pipeline"
RAW = "/home/user/raw_data.csv"
PROCESSED = "/home/user/processed_data.csv"


def test_source_and_release_binary_exist():
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} is missing."
    assert not os.path.islink(SOURCE), f"Rust source file {SOURCE} must be a regular file."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "Rust source file is empty."
    assert "fn main" in source, "Rust source does not contain a main function."

    assert os.path.isfile(BINARY), f"Release binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Release binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not an ELF executable."


def test_compiled_pipeline_and_processed_data_csv():
    with open(RAW, "rb") as f:
        original_raw = f.read()

    rng = random.SystemRandom()
    valid_f1 = [rng.randint(3, 40), rng.randint(41, 80), rng.randint(81, 120)]
    fixture = [
        [str(valid_f1[0]), "100.0", "11.5", "boundary"],
        ["", str(rng.randint(10, 90)), "22.5", "missing"],
        [str(valid_f1[1]), str(rng.randint(101, 180)), "33.5", "outlier"],
        [str(valid_f1[2]), str(rng.randint(-20, 9)), "44.5", "kept"],
    ]
    f1_mean = sum(valid_f1) / len(valid_f1)
    expected_dynamic = []
    for f1_text, f2_text, f3_text, _ in fixture:
        f2 = float(f2_text)
        if f2 > 100.0:
            continue
        f1 = float(f1_text) if f1_text else f1_mean
        expected_dynamic.append((f1 * f2, float(f3_text)))

    try:
        with open(RAW, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["f1", "f2", "f3", "f4"])
            writer.writerows(fixture)
        if os.path.exists(PROCESSED):
            os.remove(PROCESSED)

        result = subprocess.run([BINARY], cwd="/home/user/pipeline", capture_output=True, text=True)
        assert result.returncode == 0, f"Release binary failed on a generated fixture: {result.stderr}"
        assert os.path.isfile(PROCESSED), "Release binary did not create processed_data.csv."

        with open(PROCESSED, newline="") as f:
            dynamic_rows = list(csv.reader(f))
        assert dynamic_rows and dynamic_rows[0] == ["f_new", "f3"], "Generated output has the wrong columns."
        assert len(dynamic_rows[1:]) == len(expected_dynamic), "Generated output has the wrong row count."
        for actual, expected in zip(dynamic_rows[1:], expected_dynamic):
            assert len(actual) == 2, "Generated output must contain only f_new and f3."
            assert abs(float(actual[0]) - expected[0]) < 1e-5
            assert abs(float(actual[1]) - expected[1]) < 1e-5
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        if os.path.exists(PROCESSED):
            os.remove(PROCESSED)
        restore_result = subprocess.run([BINARY], cwd="/home/user/pipeline", capture_output=True, text=True)
        assert restore_result.returncode == 0, f"Release binary failed on the original dataset: {restore_result.stderr}"

    processed_data_path = "/home/user/processed_data.csv"
    assert os.path.isfile(processed_data_path), f"Processed data file {processed_data_path} is missing."

    with open(processed_data_path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Processed data file is empty."

    header = rows[0]
    assert header == ["f_new", "f3"], f"Expected header ['f_new', 'f3'], but got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows, but got {len(data_rows)}"

    expected_data = [
        (500.0, 1.0),
        (1200.0, 2.0),
        (1200.0, 4.0)
    ]

    for i, (expected_f_new, expected_f3) in enumerate(expected_data):
        actual_f_new = float(data_rows[i][0])
        actual_f3 = float(data_rows[i][1])

        assert abs(actual_f_new - expected_f_new) < 1e-5, f"Row {i+1}: Expected f_new={expected_f_new}, got {actual_f_new}"
        assert abs(actual_f3 - expected_f3) < 1e-5, f"Row {i+1}: Expected f3={expected_f3}, got {actual_f3}"


def test_experiment_artifact_json():
    artifact_path = "/home/user/experiment_artifact.json"
    assert os.path.isfile(artifact_path), f"Experiment artifact file {artifact_path} is missing."

    with open(artifact_path, 'r') as f:
        try:
            artifact = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {artifact_path} is not valid JSON.")

    assert "rows" in artifact, "Key 'rows' is missing in experiment artifact."
    assert "f_new_mean" in artifact, "Key 'f_new_mean' is missing in experiment artifact."

    assert artifact["rows"] == 3, f"Expected 'rows' to be 3, got {artifact['rows']}"

    expected_mean = 966.67
    actual_mean = artifact["f_new_mean"]
    assert isinstance(actual_mean, (int, float)), f"'f_new_mean' should be a number, got {type(actual_mean)}"
    assert abs(actual_mean - expected_mean) < 1e-2, f"Expected 'f_new_mean' to be {expected_mean}, got {actual_mean}"
TEST_EOF

if [ "$build_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
