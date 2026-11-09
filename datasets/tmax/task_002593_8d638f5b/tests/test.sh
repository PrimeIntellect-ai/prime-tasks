#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import math
import random
import subprocess
import tempfile
import pytest

PROJECT_PATH = "/home/user/pipeline"
DATASET_PATH = "/home/user/pipeline/data/dataset.csv"
OUTPUT_CSV_PATH = "/home/user/pipeline/output/normalized.csv"
METRICS_LOG_PATH = "/home/user/pipeline/output/metrics.log"
EXECUTABLE_PATH = "/home/user/pipeline/build/normalize_tool"
SOURCE_PATH = "/home/user/pipeline/src/normalize.cpp"
SCRIPT_PATH = "/home/user/pipeline/run_experiment.sh"


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}. Did you build the tool?"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable."
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable."

    for path in (OUTPUT_CSV_PATH, METRICS_LOG_PATH):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"run_experiment.sh failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}. Did you build the tool?"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "normalize_tool is not a compiled ELF executable."


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable."


def test_metrics_log():
    assert os.path.isfile(METRICS_LOG_PATH), f"Metrics log not found at {METRICS_LOG_PATH}. Did you redirect stdout?"

    assert os.path.isfile(DATASET_PATH), f"Dataset not found at {DATASET_PATH}."
    train_vals = []
    with open(DATASET_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if int(row['is_train']) == 1:
                train_vals.append(float(row['feature_1']))

    expected_min = min(train_vals)
    expected_max = max(train_vals)

    with open(METRICS_LOG_PATH, 'r') as f:
        log_content = f.read().strip()

    match = re.search(r"Feature 1:\s*min=([0-9\.\-]+),\s*max=([0-9\.\-]+)", log_content)
    assert match is not None, f"Could not parse metrics log. Content was: {log_content}"

    actual_min = float(match.group(1))
    actual_max = float(match.group(2))

    assert math.isclose(actual_min, expected_min, rel_tol=1e-5), f"Expected min={expected_min}, but got {actual_min}"
    assert math.isclose(actual_max, expected_max, rel_tol=1e-5), f"Expected max={expected_max}, but got {actual_max}"


def test_normalized_csv():
    assert os.path.isfile(OUTPUT_CSV_PATH), f"Output CSV not found at {OUTPUT_CSV_PATH}."

    assert os.path.isfile(DATASET_PATH), f"Dataset not found at {DATASET_PATH}."
    train_vals = []
    rows = []
    with open(DATASET_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
            if int(row['is_train']) == 1:
                train_vals.append(float(row['feature_1']))

    expected_min = min(train_vals)
    expected_max = max(train_vals)

    expected_scaled = {}
    expected_train = {}
    expected_ids = []
    for row in rows:
        val = float(row['feature_1'])
        scaled = (val - expected_min) / (expected_max - expected_min)
        expected_scaled[row['id']] = scaled
        expected_train[row['id']] = int(row['is_train'])
        expected_ids.append(row['id'])

    seen_ids = []
    with open(OUTPUT_CSV_PATH, 'r') as f:
        reader = csv.DictReader(f)
        assert 'feature_1_scaled' in reader.fieldnames, "Output CSV missing 'feature_1_scaled' column."
        assert reader.fieldnames == ['id', 'feature_1_scaled', 'is_train'], \
            f"Unexpected output columns: {reader.fieldnames}"

        for row in reader:
            row_id = row['id']
            seen_ids.append(row_id)
            actual_scaled = float(row['feature_1_scaled'])
            assert row_id in expected_scaled, f"Unexpected id {row_id} in output CSV."
            expected_val = expected_scaled[row_id]
            assert math.isclose(actual_scaled, expected_val, abs_tol=1e-4), \
                f"Row id={row_id}: expected scaled value {expected_val:.4f}, but got {actual_scaled:.4f}"
            assert int(row['is_train']) == expected_train[row_id], \
                f"Row id={row_id} has an incorrect is_train value."

    assert seen_ids == expected_ids, \
        f"Output must contain every input row exactly once and in input order; expected IDs {expected_ids}, got {seen_ids}."


def exercise_tool(tool_path):
    base = random.SystemRandom().randint(200, 20000)
    input_rows = [
        (701, base + 17, 1),
        (702, base - 103, 0),
        (703, base + 49, 1),
        (704, base + 211, 0),
        (705, base, 1),
    ]
    train_values = [float(value) for _, value, flag in input_rows if flag == 1]
    expected_min = min(train_values)
    expected_max = max(train_values)

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "unseen.csv")
        output_path = os.path.join(td, "normalized.csv")
        with open(input_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "feature_1", "is_train"])
            writer.writerows(input_rows)

        result = subprocess.run(
            [tool_path, input_path, output_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"normalize_tool failed on an unseen dataset. stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert re.fullmatch(
            r"Feature 1:\s*min=([0-9\.\-]+),\s*max=([0-9\.\-]+)\s*",
            result.stdout,
        ), f"Unexpected metrics output: {result.stdout!r}"
        match = re.fullmatch(
            r"Feature 1:\s*min=([0-9\.\-]+),\s*max=([0-9\.\-]+)\s*",
            result.stdout,
        )
        assert math.isclose(float(match.group(1)), expected_min, rel_tol=1e-9, abs_tol=1e-9)
        assert math.isclose(float(match.group(2)), expected_max, rel_tol=1e-9, abs_tol=1e-9)
        assert os.path.isfile(output_path), "normalize_tool did not create its requested output file."

        with open(output_path, newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["id", "feature_1_scaled", "is_train"]
            actual_rows = list(reader)

        assert len(actual_rows) == len(input_rows), \
            f"Expected {len(input_rows)} output rows, got {len(actual_rows)}."
        assert [int(r["id"]) for r in actual_rows] == [r[0] for r in input_rows]
        for actual, (row_id, value, flag) in zip(actual_rows, input_rows):
            expected = (float(value) - expected_min) / (expected_max - expected_min)
            assert int(actual["id"]) == row_id
            assert int(actual["is_train"]) == flag
            assert math.isclose(float(actual["feature_1_scaled"]), expected, abs_tol=1e-4), \
                f"Incorrect unseen-data scaling for id {row_id}."


def test_compiled_tool_on_unseen_data():
    exercise_tool(EXECUTABLE_PATH)


def test_fixed_source_on_unseen_data():
    assert os.path.isfile(SOURCE_PATH), f"Source file not found at {SOURCE_PATH}."
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "normalize_tool_from_source")
        result = subprocess.run(
            ["g++", "-std=c++17", SOURCE_PATH, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"Fixed source does not compile: {result.stderr}"
        exercise_tool(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
