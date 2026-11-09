#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import subprocess
import pytest

SOURCE = "/home/user/validate_artifacts.cpp"
EXECUTABLE = "/home/user/validate_artifacts"
EXPERIMENTS = "/home/user/experiments"
METADATA = os.path.join(EXPERIMENTS, "metadata.csv")
EMBEDDINGS = os.path.join(EXPERIMENTS, "embeddings")
REPORT = os.path.join(EXPERIMENTS, "validation_report.csv")


def test_source_file_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_validation_report_exists():
    path = REPORT
    assert os.path.isfile(path), f"Output file {path} does not exist."


def test_validation_report_content():
    path = REPORT
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Validation report is empty."

    header = rows[0]
    assert header == ["model_id", "is_valid", "distance"], f"Incorrect header: {header}"

    expected = {
        "model_A": (1, 0.0000),
        "model_B": (1, math.sqrt(5)),
        "model_C": (0, -1.0000),
        "model_D": (0, -1.0000),
        "model_E": (1, math.sqrt(5)),
    }

    data_rows = rows[1:]
    assert len(data_rows) == 5, f"Expected 5 data rows, got {len(data_rows)}"

    seen_models = set()
    for row in data_rows:
        assert len(row) == 3, f"Row does not have exactly 3 columns: {row}"
        model_id, is_valid_str, distance_str = row

        assert model_id in expected, f"Unexpected model_id: {model_id}"
        seen_models.add(model_id)

        expected_is_valid, expected_distance = expected[model_id]

        assert int(is_valid_str) == expected_is_valid, f"Incorrect is_valid for {model_id}: expected {expected_is_valid}, got {is_valid_str}"

        distance = float(distance_str)
        assert abs(distance - expected_distance) < 1e-3, f"Incorrect distance for {model_id}: expected ~{expected_distance:.4f}, got {distance}"

        if "." in distance_str:
            decimals = len(distance_str.split(".")[1])
            assert decimals == 4, f"Distance for {model_id} not formatted to exactly 4 decimal places: {distance_str}"
        else:
            pytest.fail(f"Distance for {model_id} does not contain a decimal point: {distance_str}")

    assert seen_models == set(expected.keys()), "Not all expected models were found in the report."


def test_compile_execute_and_join_dynamic_inputs():
    token = secrets.token_hex(10)
    cases = [
        (f"fresh_zero_{token}", [0.0, 0.0, 0.0, 0.0, 0.0], "0 0 0 0 0"),
        (f"fresh_mix_{token}", [2.25, -1.5, 3.0, 0.5, 4.75], "2.25 -1.5 3.0 0.5 4.75"),
        (f"fresh_ref_{token}", [1.0, 1.0, 1.0, 1.0, 1.0], "1 1 1 1 1"),
        (f"bad_short_{token}", None, "1 2 3 4"),
        (f"bad_long_{token}", None, "1 2 3 4 5 6"),
        (f"bad_text_{token}", None, "1 1 invalid 1 1"),
        (f"bad_nan_{token}", None, "1 NaN 1 1 1"),
        (f"bad_inf_{token}", None, "1 1 Inf 1 1"),
    ]

    metadata_backup = open(METADATA, "rb").read()
    report_backup = open(REPORT, "rb").read() if os.path.exists(REPORT) else None
    created_files = []

    try:
        metadata_rows = [["model_id", "epoch", "embedding_file"]]
        expected = {}
        for index, (model_id, vector, contents) in enumerate(cases):
            filename = f"dynamic_{token}_{index}.txt"
            path = os.path.join(EMBEDDINGS, filename)
            with open(path, "w", newline="") as f:
                f.write(contents + "\n")
            created_files.append(path)
            metadata_rows.append([model_id, str(100 + index), filename])
            if vector is None:
                expected[model_id] = ("0", "-1.0000")
            else:
                distance = math.sqrt(sum((value - 1.0) ** 2 for value in vector))
                expected[model_id] = ("1", f"{distance:.4f}")

        with open(METADATA, "w", newline="") as f:
            csv.writer(f).writerows(metadata_rows)

        if os.path.exists(REPORT):
            os.remove(REPORT)

        compilation = subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", EXECUTABLE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compilation.returncode == 0, f"C++ source did not compile:\n{compilation.stderr}"
        assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)

        execution = subprocess.run(
            [EXECUTABLE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert execution.returncode == 0, f"Compiled utility failed:\n{execution.stderr}"
        assert os.path.isfile(REPORT), "Compiled utility did not generate validation_report.csv"

        with open(REPORT, "r", newline="") as f:
            rows = list(csv.reader(f))

        assert rows and rows[0] == ["model_id", "is_valid", "distance"], f"Incorrect dynamic report header: {rows[:1]}"
        assert len(rows) == len(cases) + 1, f"Expected {len(cases)} dynamic data rows, got {len(rows) - 1}"

        actual = {}
        for row in rows[1:]:
            assert len(row) == 3, f"Dynamic row does not have exactly 3 columns: {row}"
            model_id, is_valid, distance = row
            assert model_id in expected, f"Unexpected dynamic model_id: {model_id}"
            assert model_id not in actual, f"Duplicate dynamic model_id: {model_id}"
            assert is_valid in ("0", "1"), f"Invalid is_valid value for {model_id}: {is_valid}"
            assert re.fullmatch(r"-?\d+\.\d{4}", distance), f"Distance is not formatted to exactly four decimals: {distance}"
            actual[model_id] = (is_valid, distance)

        assert actual == expected, f"Dynamic report mismatch. Expected {expected}, got {actual}"
    finally:
        with open(METADATA, "wb") as f:
            f.write(metadata_backup)
        if report_backup is None:
            if os.path.exists(REPORT):
                os.remove(REPORT)
        else:
            with open(REPORT, "wb") as f:
                f.write(report_backup)
        for path in created_files:
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
