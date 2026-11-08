#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
PRIMARY_INPUT = "/home/user/raw_measurements.csv"
PRIMARY_OUTPUT = "/home/user/output"


@pytest.fixture(scope="session", autouse=True)
def execute_primary_pipeline():
    """Regenerate the required outputs by actually executing the submitted pipeline."""
    assert os.path.exists(SCRIPT_PATH), f"Pipeline script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Pipeline script {SCRIPT_PATH} is not executable."

    shutil.rmtree(PRIMARY_OUTPUT, ignore_errors=True)
    result = subprocess.run(
        [SCRIPT_PATH, PRIMARY_INPUT, PRIMARY_OUTPUT],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline failed on the provided input with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_pipeline_script_exists_and_executable():
    """Verify the pipeline script exists and is executable."""
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Pipeline script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."


def test_cleaned_measurements_content():
    """Verify the cleaned_measurements.csv contains exactly the valid rows."""
    output_csv = "/home/user/output/cleaned_measurements.csv"
    assert os.path.exists(output_csv), f"Output file {output_csv} does not exist."

    with open(output_csv, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "id,value,category",
        "1,12.34567,A",
        "3,-9.87654,A",
        "6,45.6789,B",
        "8,0.00000,C",
        "10,3.14159,C",
        "11,50.0,A"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in cleaned CSV, found {len(lines)}."
    assert lines[0] == "id,value,category", "Header of cleaned CSV is missing or incorrect."

    for i in range(1, len(expected_lines)):
        expected_parts = expected_lines[i].split(',')
        actual_parts = lines[i].split(',')

        assert len(actual_parts) == 3, f"Row {i} does not have 3 columns."
        assert actual_parts[0] == expected_parts[0], f"Row {i} ID mismatch: expected {expected_parts[0]}, got {actual_parts[0]}"
        assert actual_parts[2] == expected_parts[2], f"Row {i} category mismatch: expected {expected_parts[2]}, got {actual_parts[2]}"

        expected_val = float(expected_parts[1])
        actual_val = float(actual_parts[1])
        assert math.isclose(actual_val, expected_val, rel_tol=1e-9), \
            f"Row {i} value mismatch: expected {expected_val}, got {actual_val}"


def test_stats_json_content():
    """Verify the stats.json contains the correct rounded mean and variance."""
    output_json = "/home/user/output/stats.json"
    assert os.path.exists(output_json), f"Output file {output_json} does not exist."

    with open(output_json, "r") as f:
        try:
            stats = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{output_json} is not valid JSON."

    expected_stats = {
        "A": {"mean": 17.4897, "variance": 610.7649},
        "B": {"mean": 45.6789, "variance": 0.0},
        "C": {"mean": 1.5708, "variance": 2.4674}
    }

    assert sorted(stats.keys()) == ["A", "B", "C"], "JSON keys must be exactly 'A', 'B', 'C' and alphabetically ordered."

    for cat, expected in expected_stats.items():
        assert "mean" in stats[cat], f"Missing 'mean' for category {cat}."
        assert "variance" in stats[cat], f"Missing 'variance' for category {cat}."

        actual_mean = stats[cat]["mean"]
        actual_var = stats[cat]["variance"]

        assert isinstance(actual_mean, (int, float)), f"Mean for {cat} must be a number."
        assert isinstance(actual_var, (int, float)), f"Variance for {cat} must be a number."

        assert math.isclose(actual_mean, expected["mean"], abs_tol=1e-4), \
            f"Mean for {cat} is incorrect. Expected {expected['mean']}, got {actual_mean}."
        assert math.isclose(actual_var, expected["variance"], abs_tol=1e-4), \
            f"Variance for {cat} is incorrect. Expected {expected['variance']}, got {actual_var}."


def test_pipeline_on_fresh_unseen_input():
    """Exercise the pipeline on generated data and independently derive all answers."""
    rng = secrets.SystemRandom()
    generated_values = [
        ("Alpha", rng.uniform(-90.0, 90.0)),
        ("Middle", rng.uniform(-90.0, 90.0)),
        ("Zulu", rng.uniform(-90.0, 90.0)),
        ("Alpha", rng.uniform(-90.0, 90.0)),
        ("Middle", rng.uniform(-90.0, 90.0)),
        ("Zulu", rng.uniform(-90.0, 90.0)),
        ("Alpha", rng.uniform(-90.0, 90.0)),
    ]

    rows = [["id", "value", "category"]]
    next_id = 1000
    for category, value in generated_values:
        rows.append([str(next_id), f"{value:.10f}", category])
        next_id += 1

    rows.extend([
        [str(next_id), "-100.0", "Middle"],
        [str(next_id + 1), "100.0", "Zulu"],
        [str(next_id + 2), "NaN", "Ghost"],
        [str(next_id + 3), "inf", "Ghost"],
        [str(next_id + 4), "-Infinity", "Ghost"],
        [str(next_id + 5), "1e309", "Ghost"],
        [str(next_id + 6), "not-a-number", "Alpha"],
        [str(next_id + 7), "100.0000001", "Zulu"],
        [str(next_id + 8), "-100.0000001", "Middle"],
        [str(next_id + 9), "-0.0", "Alpha"],
    ])

    workdir = tempfile.mkdtemp(prefix="etl-verifier-")
    try:
        input_path = os.path.join(workdir, "measurements.csv")
        output_dir = os.path.join(workdir, "new-output-directory")
        with open(input_path, "w", newline="") as f:
            csv.writer(f, lineterminator="\n").writerows(rows)

        expected_rows = []
        grouped = {}
        for row in rows[1:]:
            try:
                value = float(row[1])
            except ValueError:
                continue
            if not math.isfinite(value) or value < -100.0 or value > 100.0:
                continue
            expected_rows.append((row[0], value, row[2]))
            grouped.setdefault(row[2], []).append(value)

        expected_stats = {}
        for category in sorted(grouped):
            values = grouped[category]
            mean = math.fsum(values) / len(values)
            variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
            expected_stats[category] = {
                "mean": round(mean, 4),
                "variance": round(variance, 4),
            }

        result = subprocess.run(
            [SCRIPT_PATH, input_path, output_dir],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline failed on generated input with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        cleaned_path = os.path.join(output_dir, "cleaned_measurements.csv")
        stats_path = os.path.join(output_dir, "stats.json")
        assert os.path.isfile(cleaned_path), "Pipeline did not create cleaned_measurements.csv."
        assert os.path.isfile(stats_path), "Pipeline did not create stats.json."

        with open(cleaned_path, newline="") as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows and actual_rows[0] == ["id", "value", "category"]
        assert len(actual_rows) == len(expected_rows) + 1
        for index, (actual, expected) in enumerate(zip(actual_rows[1:], expected_rows), 1):
            assert len(actual) == 3, f"Generated-output row {index} does not have 3 columns."
            assert actual[0] == expected[0], f"Generated-output row {index} has the wrong ID."
            assert actual[2] == expected[2], f"Generated-output row {index} has the wrong category."
            try:
                actual_value = float(actual[1])
            except ValueError:
                pytest.fail(f"Generated-output row {index} has a non-float value.")
            assert math.isfinite(actual_value)
            assert math.isclose(actual_value, expected[1], rel_tol=1e-12, abs_tol=1e-12), \
                f"Generated-output row {index} has the wrong value."

        with open(stats_path) as f:
            actual_stats = json.load(f)
        assert list(actual_stats.keys()) == sorted(expected_stats.keys()), \
            "Statistics categories are missing, extra, or not alphabetically ordered."
        for category, expected in expected_stats.items():
            assert set(actual_stats[category].keys()) == {"mean", "variance"}
            for field in ("mean", "variance"):
                actual = actual_stats[category][field]
                assert type(actual) in (int, float), f"{field} for {category} must be numeric."
                assert math.isfinite(actual), f"{field} for {category} must be finite."
                assert actual == expected[field], \
                    f"Wrong {field} for {category}: expected {expected[field]}, got {actual}."
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
