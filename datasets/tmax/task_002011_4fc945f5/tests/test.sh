#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

RAW_PATH = Path("/home/user/raw_data.csv")
CLEAN_PATH = Path("/home/user/clean_data.csv")
JSON_PATH = Path("/home/user/experiment.json")
PROJECT_PATH = Path("/home/user/data_prep")
BINARY_PATH = PROJECT_PATH / "target/release/data_prep"

EXPECTED_RAW = b"""id,category,clicks,response_time
1,A,10,100.5
2,B,,200.0
3,A,15,150.2
4,C,20,120.0
5,B,,180.5
6,A,5,90.0
7,C,,210.0
8,B,12,130.5
9,A,8,110.0
10,C,25,105.0
"""


def read_csv(path):
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        return reader.fieldnames, rows


def assert_cleaned_rows(fieldnames, rows, expected_rows):
    assert fieldnames == ["id", "category", "clicks", "response_time"], \
        f"Unexpected CSV columns/order: {fieldnames}"
    assert len(rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows, got {len(rows)}"

    for i, (row, expected) in enumerate(zip(rows, expected_rows), 1):
        assert None not in row, f"Row {i} has extra CSV fields"
        assert row["id"] == expected["id"], f"Row {i}: id was changed"
        assert row["category"] == expected["category"], f"Row {i}: category was changed"

        clicks_val = row["clicks"]
        assert "." not in clicks_val, \
            f"Row {i}: 'clicks' value '{clicks_val}' contains a decimal point. It must be strictly integer."
        try:
            clicks_int = int(clicks_val)
        except ValueError:
            assert False, f"Row {i}: 'clicks' value '{clicks_val}' is not a valid integer."
        assert re.fullmatch(r"-?(?:0|[1-9][0-9]*)", clicks_val), \
            f"Row {i}: clicks is not formatted as a strict integer"
        assert clicks_int == expected["clicks"], \
            f"Row {i}: expected clicks {expected['clicks']}, got {clicks_int}"

        try:
            response_time = float(row["response_time"])
        except ValueError:
            assert False, f"Row {i}: invalid response_time {row['response_time']!r}"
        assert math.isclose(response_time, expected["response_time"], rel_tol=0, abs_tol=1e-12), \
            f"Row {i}: response_time was changed"


def expected_from_input(path):
    fieldnames, rows = read_csv(path)
    assert fieldnames == ["id", "category", "clicks", "response_time"]
    return [
        {
            "id": row["id"],
            "category": row["category"],
            "clicks": -1 if row["clicks"] == "" else int(row["clicks"]),
            "response_time": float(row["response_time"]),
        }
        for row in rows
    ]


def test_raw_data_was_not_modified():
    assert RAW_PATH.is_file(), f"Missing raw data file at {RAW_PATH}"
    assert RAW_PATH.read_bytes() == EXPECTED_RAW, "The original raw_data.csv was modified"


def test_release_rust_cleaner_exists_and_runs():
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "Missing Rust Cargo.toml"
    assert (PROJECT_PATH / "src/main.rs").is_file(), "Missing Rust src/main.rs"
    assert BINARY_PATH.is_file(), "Missing release build at target/release/data_prep"
    assert not BINARY_PATH.is_symlink(), "Release artifact must be a real binary, not a symlink"
    assert os.access(BINARY_PATH, os.X_OK), "Release build is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not an ELF executable"

    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)
    generated = [
        [str(rng.randrange(10000, 99999)), f"A,{token}", "", f"{rng.randrange(50, 500)}.{rng.randrange(1, 10)}"],
        [str(rng.randrange(10000, 99999)), f"B-{token}", str(rng.randrange(1, 100000)), f"{rng.randrange(50, 500)}.{rng.randrange(1, 10)}"],
        [str(rng.randrange(10000, 99999)), f"C-{token}", "", f"{rng.randrange(50, 500)}.{rng.randrange(1, 10)}"],
        [str(rng.randrange(10000, 99999)), f"D-{token}", "0", f"{rng.randrange(50, 500)}.{rng.randrange(1, 10)}"],
    ]

    with tempfile.TemporaryDirectory() as td:
        input_path = Path(td) / "generated_input.csv"
        output_path = Path(td) / "generated_output.csv"
        with open(input_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "category", "clicks", "response_time"])
            writer.writerows(generated)

        result = subprocess.run(
            [str(BINARY_PATH), str(input_path), str(output_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"Release cleaner failed: {result.stderr}"
        assert output_path.is_file(), "Release cleaner did not create its requested output"
        fields, rows = read_csv(output_path)
        assert_cleaned_rows(fields, rows, expected_from_input(input_path))


def test_clean_data_csv():
    assert CLEAN_PATH.is_file(), f"Missing clean data file at {CLEAN_PATH}"
    fieldnames, rows = read_csv(CLEAN_PATH)
    assert len(rows) > 0, "Clean data file is empty"
    assert_cleaned_rows(fieldnames, rows, expected_from_input(RAW_PATH))

    with tempfile.TemporaryDirectory() as td:
        reproduced = Path(td) / "clean_data.csv"
        result = subprocess.run(
            [str(BINARY_PATH), str(RAW_PATH), str(reproduced)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"Release cleaner failed on raw_data.csv: {result.stderr}"
        fields2, rows2 = read_csv(reproduced)
        assert_cleaned_rows(fields2, rows2, expected_from_input(RAW_PATH))
        assert rows2 == rows, "Submitted clean_data.csv does not match the release cleaner's output"


def test_experiment_json():
    assert JSON_PATH.is_file(), f"Missing experiment log at {JSON_PATH}"
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} is not valid JSON."

    expected_keys = {"cleaned_rows", "mean_response_time", "ci_lower", "ci_upper"}
    for key in expected_keys:
        assert key in data, f"Missing key '{key}' in experiment.json"
    assert set(data) == expected_keys, f"experiment.json must contain exactly {sorted(expected_keys)}"

    assert CLEAN_PATH.is_file(), "Cannot validate json values without clean_data.csv"
    _, rows = read_csv(CLEAN_PATH)
    n = len(rows)
    assert data["cleaned_rows"] == n, \
        f"Expected cleaned_rows to be {n}, got {data['cleaned_rows']}"

    response_times = []
    for row in rows:
        assert "response_time" in row, "Missing 'response_time' column in clean data"
        response_times.append(float(row["response_time"]))

    mean = sum(response_times) / n
    variance = sum((x - mean) ** 2 for x in response_times) / (n - 1) if n > 1 else 0
    std_dev = math.sqrt(variance)
    margin_of_error = 1.96 * (std_dev / math.sqrt(n))
    ci_lower = mean - margin_of_error
    ci_upper = mean + margin_of_error

    assert math.isclose(data["mean_response_time"], mean, rel_tol=1e-2), \
        f"Expected mean_response_time ~ {mean:.3f}, got {data['mean_response_time']}"
    assert math.isclose(data["ci_lower"], ci_lower, rel_tol=1e-2), \
        f"Expected ci_lower ~ {ci_lower:.3f}, got {data['ci_lower']}"
    assert math.isclose(data["ci_upper"], ci_upper, rel_tol=1e-2), \
        f"Expected ci_upper ~ {ci_upper:.3f}, got {data['ci_upper']}"

    assert not isinstance(data["cleaned_rows"], bool) and isinstance(data["cleaned_rows"], int)
    for key, expected in [
        ("mean_response_time", mean),
        ("ci_lower", ci_lower),
        ("ci_upper", ci_upper),
    ]:
        assert not isinstance(data[key], bool) and isinstance(data[key], (int, float)), \
            f"{key} must be numeric"
        assert data[key] == round(expected, 3), \
            f"{key} must equal {round(expected, 3)} after rounding to 3 decimal places"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
