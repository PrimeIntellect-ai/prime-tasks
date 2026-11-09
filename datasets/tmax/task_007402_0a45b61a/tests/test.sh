#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import statistics
import subprocess

import pytest


@pytest.fixture(scope="session", autouse=True)
def run_etl_script():
    """Run the student's ETL bash script before checking the state."""
    script_path = "/home/user/run_etl.sh"
    etl_path = "/home/user/etl.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."
    assert os.path.isfile(etl_path), f"The ETL script {etl_path} does not exist."

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_etl.sh failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def _venv_python():
    for path in ("/home/user/venv/bin/python", "/home/user/venv/bin/python3"):
        if os.path.isfile(path):
            return path
    pytest.fail("Python executable not found in the virtual environment.")


def test_venv_created():
    """Test that the virtual environment was created."""
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} does not exist."
    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin) or os.path.isfile(python_bin + "3"), "Python executable not found in the virtual environment."


def test_pandas_installed_in_venv():
    result = subprocess.run(
        [_venv_python(), "-c", "import pandas; print(pandas.__version__)"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"pandas is not installed in the virtual environment.\nStderr: {result.stderr}"


def test_output_file_exists():
    """Test that the output.jsonl file was created."""
    output_path = "/home/user/output.jsonl"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."


def test_output_file_content():
    """Test that the output.jsonl file contains the correct processed data."""
    output_path = "/home/user/output.jsonl"

    expected_data = [
        {"user_id": 1, "name": "Alice", "age": 25.0, "total_amount": 150.5},
        {"user_id": 2, "name": "Bob", "age": 30.0, "total_amount": 200.0},
        {"user_id": 5, "name": "Eve", "age": 30.0, "total_amount": 75.25}
    ]

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_data), f"Expected {len(expected_data)} lines in output.jsonl, but found {len(lines)}."

    for i, (expected, line) in enumerate(zip(expected_data, lines)):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in output.jsonl is not valid JSON: {line}")

        assert "user_id" in parsed, f"Line {i+1} missing 'user_id'"
        assert "name" in parsed, f"Line {i+1} missing 'name'"
        assert "age" in parsed, f"Line {i+1} missing 'age'"
        assert "total_amount" in parsed, f"Line {i+1} missing 'total_amount'"
        assert set(parsed) == {"user_id", "name", "age", "total_amount"}, f"Line {i+1} has incorrect keys: {set(parsed)}"

        assert parsed["user_id"] == expected["user_id"], f"Line {i+1}: expected user_id {expected['user_id']}, got {parsed['user_id']}"
        assert parsed["name"] == expected["name"], f"Line {i+1}: expected name '{expected['name']}', got '{parsed['name']}'"
        assert float(parsed["age"]) == expected["age"], f"Line {i+1}: expected age {expected['age']}, got {parsed['age']}"
        assert float(parsed["total_amount"]) == expected["total_amount"], f"Line {i+1}: expected total_amount {expected['total_amount']}, got {parsed['total_amount']}"
        assert type(parsed["user_id"]) is int, f"Line {i+1}: user_id must be an integer"
        assert type(parsed["name"]) is str, f"Line {i+1}: name must be a string"
        assert type(parsed["age"]) is float, f"Line {i+1}: age must be a float"
        assert type(parsed["total_amount"]) is float, f"Line {i+1}: total_amount must be a float"


def _write_case(seed):
    rng = random.Random(seed)
    ids = rng.sample(range(1000, 9000), 8)
    valid_ages = [1, 120, rng.randint(18, 45), rng.randint(60, 95)]
    users = [
        [ids[0], f"BoundaryLow_{seed}", str(valid_ages[0]), "2024-01-01"],
        [ids[1], f"BoundaryHigh_{seed}", str(valid_ages[1]), "2024-01-02"],
        [ids[2], f"ValidA_{seed}", str(valid_ages[2]), "2024-01-03"],
        [ids[3], f"ValidB_{seed}", str(valid_ages[3]), "2024-01-04"],
        [ids[4], f"MissingA_{seed}", "", "2024-01-05"],
        [ids[5], f"MissingB_{seed}", "", "2024-01-06"],
        [ids[6], f"TooLow_{seed}", "0", "2024-01-07"],
        [ids[7], f"TooHigh_{seed}", "121", "2024-01-08"],
    ]

    def amount():
        return f"{rng.randint(100, 20000) / 100:.2f}"

    purchases = []
    for uid in ids[:6]:
        purchases.append([uid, amount(), "2024-02-01"])
    purchases.extend([
        [ids[0], amount(), "2024-02-02"],
        [ids[4], amount(), "2024-02-03"],
        [ids[1], "-9.75", "2024-02-04"],
        [ids[6], amount(), "2024-02-05"],
        [ids[7], amount(), "2024-02-06"],
        [99999, amount(), "2024-02-07"],
    ])
    rng.shuffle(users)
    rng.shuffle(purchases)

    with open("/home/user/data/users.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["user_id", "name", "age", "signup_date"])
        writer.writerows(users)
    with open("/home/user/data/purchases.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["user_id", "amount", "purchase_date"])
        writer.writerows(purchases)


def _derive_expected():
    with open("/home/user/data/users.csv", newline="") as f:
        raw_users = list(csv.DictReader(f))
    with open("/home/user/data/purchases.csv", newline="") as f:
        raw_purchases = list(csv.DictReader(f))

    valid_ages = [
        float(row["age"])
        for row in raw_users
        if row["age"].strip() and 1 <= float(row["age"]) <= 120
    ]
    median_age = float(statistics.median(valid_ages))

    cleaned_users = []
    for row in raw_users:
        age = median_age if not row["age"].strip() else float(row["age"])
        if 1 <= age <= 120:
            cleaned_users.append((int(row["user_id"]), row["name"], float(age)))

    purchases_by_id = {}
    for row in raw_purchases:
        value = float(row["amount"])
        if value >= 0:
            purchases_by_id.setdefault(int(row["user_id"]), []).append(value)

    grouped = {}
    for uid, name, age in cleaned_users:
        for value in purchases_by_id.get(uid, []):
            key = (uid, name, age)
            grouped[key] = grouped.get(key, 0.0) + value

    return [
        {"user_id": uid, "name": name, "age": float(age), "total_amount": float(total)}
        for (uid, name, age), total in sorted(grouped.items(), key=lambda item: item[0][0])
    ]


def _assert_dynamic_output(expected):
    with open("/home/user/output.jsonl") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected), f"Expected {len(expected)} output rows, found {len(lines)}"

    parsed_rows = []
    for index, line in enumerate(lines, 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Dynamic output line {index} is not valid JSON: {exc}")
        assert set(row) == {"user_id", "name", "age", "total_amount"}, f"Dynamic output line {index} has incorrect keys"
        assert type(row["user_id"]) is int, f"Dynamic output line {index}: user_id must be an integer"
        assert type(row["name"]) is str, f"Dynamic output line {index}: name must be a string"
        assert type(row["age"]) is float, f"Dynamic output line {index}: age must be a float"
        assert type(row["total_amount"]) is float, f"Dynamic output line {index}: total_amount must be a float"
        parsed_rows.append(row)

    assert [row["user_id"] for row in parsed_rows] == sorted(row["user_id"] for row in parsed_rows), "Output is not sorted by user_id"
    for actual, wanted in zip(parsed_rows, expected):
        assert actual["user_id"] == wanted["user_id"]
        assert actual["name"] == wanted["name"]
        assert math.isclose(actual["age"], wanted["age"], rel_tol=0, abs_tol=1e-9)
        assert math.isclose(actual["total_amount"], wanted["total_amount"], rel_tol=1e-9, abs_tol=1e-9)


def test_etl_on_generated_inputs():
    users_path = "/home/user/data/users.csv"
    purchases_path = "/home/user/data/purchases.csv"
    with open(users_path, "rb") as f:
        original_users = f.read()
    with open(purchases_path, "rb") as f:
        original_purchases = f.read()

    try:
        # Exercise the unattended runner on data not known until verification.
        _write_case(int.from_bytes(os.urandom(4), "big"))
        expected = _derive_expected()
        result = subprocess.run(["/home/user/run_etl.sh"], capture_output=True, text=True)
        assert result.returncode == 0, f"run_etl.sh failed on generated input.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        _assert_dynamic_output(expected)

        # Exercise etl.py itself with a second independent generated dataset.
        _write_case(int.from_bytes(os.urandom(4), "big"))
        expected = _derive_expected()
        result = subprocess.run(
            [_venv_python(), "/home/user/etl.py"],
            cwd="/home/user",
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"etl.py failed on generated input.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        _assert_dynamic_output(expected)
    finally:
        with open(users_path, "wb") as f:
            f.write(original_users)
        with open(purchases_path, "wb") as f:
            f.write(original_purchases)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
