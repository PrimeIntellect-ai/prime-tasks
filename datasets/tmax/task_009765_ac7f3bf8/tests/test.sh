#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
from decimal import Decimal

import pytest

HOME = "/home/user"
HEADER = "id,token_count,avg_token_length,rating"


def derive_expected(raw_path, min_tokens):
    expected = []
    with open(raw_path, newline="") as f:
        for row in csv.DictReader(f):
            tokens = row["review_text"].split(" ")
            if len(tokens) >= min_tokens:
                expected.append({
                    "id": row["id"],
                    "token_count": len(tokens),
                    "avg": Decimal(sum(len(token) for token in tokens)) / Decimal(len(tokens)),
                    "rating": row["rating"],
                })
    return expected


def assert_csv_matches(csv_path, expected):
    assert os.path.isfile(csv_path), f"{csv_path} is missing."
    with open(csv_path, newline="") as f:
        rows = list(csv.reader(f))

    assert rows, f"{csv_path} is empty."
    assert ",".join(rows[0]) == HEADER, f"Header of {csv_path} is incorrect."
    assert len(rows) == len(expected) + 1, f"Unexpected number of rows in {csv_path}."

    actual = {}
    for row in rows[1:]:
        assert len(row) == 4, f"Malformed row in {csv_path}: {row}"
        row_id, token_count, avg, rating = row
        assert row_id not in actual, f"Duplicate id={row_id} in {csv_path}."
        assert re.fullmatch(r"-?\d+\.\d{2}", avg), f"Average must have exactly two decimals: {avg}"
        actual[row_id] = (int(token_count), Decimal(avg), rating)

    assert set(actual) == {row["id"] for row in expected}, f"Incorrect ids in {csv_path}."
    for row in expected:
        count, avg, rating = actual[row["id"]]
        assert count == row["token_count"], f"Incorrect token count for id={row['id']}."
        assert rating == row["rating"], f"Incorrect rating for id={row['id']}."
        assert abs(avg - row["avg"]) <= Decimal("0.005"), f"Incorrect average for id={row['id']}."


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_and_compile_source():
    assert os.path.isfile(f"{HOME}/run_pipeline.sh"), "/home/user/run_pipeline.sh script is missing."
    assert os.path.isfile(f"{HOME}/processor.cpp"), "/home/user/processor.cpp is missing."

    shutil.rmtree(f"{HOME}/processed", ignore_errors=True)
    shutil.rmtree(f"{HOME}/experiments", ignore_errors=True)
    for path in (f"{HOME}/processor", f"{HOME}/reproducibility_check.txt"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["bash", f"{HOME}/run_pipeline.sh"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}"
    assert os.path.isfile(f"{HOME}/processor"), "The pipeline did not create /home/user/processor."
    assert os.access(f"{HOME}/processor", os.X_OK), "/home/user/processor is not executable."
    with open(f"{HOME}/processor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/processor is not a compiled ELF executable."

    compile_result = subprocess.run(
        ["g++", "-O3", f"{HOME}/processor.cpp", "-o", "/tmp/verified_processor"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"processor.cpp does not compile with g++ -O3:\n{compile_result.stdout}"


def test_directories_and_scripts_exist():
    """Test that required directories and scripts exist."""
    assert os.path.isdir("/home/user/processed"), "/home/user/processed directory is missing."
    assert os.path.isdir("/home/user/experiments"), "/home/user/experiments directory is missing."
    assert os.path.isfile("/home/user/run_pipeline.sh"), "/home/user/run_pipeline.sh script is missing."
    assert os.path.isfile("/home/user/processor.cpp"), "/home/user/processor.cpp is missing."


def test_json_experiments():
    """Test the contents of the experiment JSON files."""
    expected_results = {
        5: {"kept_rows": 8},
        10: {"kept_rows": 0},
        15: {"kept_rows": 0}
    }

    for min_tokens, expected in expected_results.items():
        json_path = f"/home/user/experiments/run_{min_tokens}.json"
        assert os.path.isfile(json_path), f"Experiment JSON {json_path} is missing."

        with open(json_path, "r") as f:
            content = f.read()

        try:
            data = json.loads(content)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

        assert data.get("min_tokens") == min_tokens, f"Expected min_tokens={min_tokens} in {json_path}."
        assert data.get("total_rows") == 10, f"Expected total_rows=10 in {json_path}."
        assert data.get("kept_rows") == expected["kept_rows"], f"Expected kept_rows={expected['kept_rows']} in {json_path}."


def test_csv_filtered_5():
    """Test the contents of filtered_5.csv."""
    csv_path = "/home/user/processed/filtered_5.csv"
    assert os.path.isfile(csv_path), f"{csv_path} is missing."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 9, f"Expected 9 lines (1 header + 8 data rows) in {csv_path}, found {len(lines)}."
    assert lines[0] == "id,token_count,avg_token_length,rating", "Header of filtered_5.csv is incorrect."
    assert "1,5,3.80,5" in lines, f"Missing or incorrect row for id=1 in {csv_path}."
    id3_found = any(re.match(r"^3,8,4\.1[23],5$", line) for line in lines)
    assert id3_found, f"Missing or incorrect row for id=3 in {csv_path}."
    assert "5,8,5.25,3" in lines, f"Missing or incorrect row for id=5 in {csv_path}."


def test_csv_filtered_10_and_15():
    """Test that filtered_10.csv and filtered_15.csv only contain the header."""
    for min_tokens in [10, 15]:
        csv_path = f"/home/user/processed/filtered_{min_tokens}.csv"
        assert os.path.isfile(csv_path), f"{csv_path} is missing."
        with open(csv_path, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
        assert len(lines) == 1, f"Expected only 1 header line in {csv_path}, found {len(lines)}."
        assert lines[0] == "id,token_count,avg_token_length,rating", f"Header of {csv_path} is incorrect."


def test_all_pipeline_outputs_are_derived_from_raw_data():
    with open(f"{HOME}/raw_data.csv", newline="") as f:
        total_rows = sum(1 for _ in csv.DictReader(f))

    for min_tokens in (5, 10, 15):
        expected = derive_expected(f"{HOME}/raw_data.csv", min_tokens)
        assert_csv_matches(f"{HOME}/processed/filtered_{min_tokens}.csv", expected)

        json_path = f"{HOME}/experiments/run_{min_tokens}.json"
        exact = f'{{"min_tokens": {min_tokens}, "total_rows": {total_rows}, "kept_rows": {len(expected)}}}'
        with open(json_path) as f:
            assert f.read().strip() == exact, f"Incorrect JSON format or values in {json_path}."


def test_reproducibility_check():
    """Test that the reproducibility check file exists and is populated."""
    check_path = "/home/user/reproducibility_check.txt"
    assert os.path.isfile(check_path), f"{check_path} is missing."

    with open(check_path, "r") as f:
        content = f.read().strip()

    assert len(content) > 0, f"{check_path} is empty."
    lines = content.split('\n')
    assert len(lines) == 3, f"Expected 3 lines in {check_path}, found {len(lines)}."

    expected_paths = {f"{HOME}/processed/filtered_{n}.csv" for n in (5, 10, 15)}
    seen_paths = set()
    for line in lines:
        assert re.match(r"^[a-f0-9]{64}\s+.*filtered_\d+\.csv$", line), f"Invalid sha256sum line format: {line}"
        match = re.fullmatch(r"([a-f0-9]{64})\s+(.+)", line)
        assert match is not None
        claimed_hash, path = match.groups()
        assert path in expected_paths, f"Unexpected checksum path: {path}"
        assert path not in seen_paths, f"Duplicate checksum path: {path}"
        seen_paths.add(path)
        with open(path, "rb") as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        assert claimed_hash == actual_hash, f"Incorrect SHA256 checksum for {path}."
    assert seen_paths == expected_paths, "Checksums do not cover exactly the three requested CSV files."


def test_processors_on_fresh_input():
    raw_path = f"{HOME}/raw_data.csv"
    with open(raw_path, "rb") as f:
        original = f.read()

    fresh = (
        'id,review_text,rating,timestamp\n'
        '101,"aa b ccc",4,1\n'
        '102,"one two",2,2\n'
        '103,"x y z q",5,3\n'
        '104,"hello",1,4\n'
    ).encode()

    try:
        with open(raw_path, "wb") as f:
            f.write(fresh)
        expected = derive_expected(raw_path, 3)

        for executable in (f"{HOME}/processor", "/tmp/verified_processor"):
            for path in (f"{HOME}/processed/filtered_3.csv", f"{HOME}/experiments/run_3.json"):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass

            result = subprocess.run(
                [executable, "3"],
                cwd=HOME,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=20,
            )
            assert result.returncode == 0, f"{executable} failed on fresh input:\n{result.stdout}"
            assert_csv_matches(f"{HOME}/processed/filtered_3.csv", expected)

            json_path = f"{HOME}/experiments/run_3.json"
            assert os.path.isfile(json_path), f"{executable} did not produce {json_path}."
            with open(json_path) as f:
                content = f.read().strip()
            assert content == '{"min_tokens": 3, "total_rows": 4, "kept_rows": 2}'
    finally:
        with open(raw_path, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
