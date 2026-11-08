#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import subprocess

import pytest

SOURCE_PATH = "/home/user/process_experiments.cpp"
BINARY_PATH = "/home/user/process_experiments"
CSV_PATH = "/home/user/experiments.csv"
JSONL_PATH = "/home/user/tracked_artifacts.jsonl"
LOG_PATH = "/home/user/invalid_rows.log"


def test_cpp_source_uses_nlohmann_json():
    assert os.path.exists(SOURCE_PATH), f"The file {SOURCE_PATH} is missing."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."

    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    # Ignore comments when checking the required dependency is actually referenced.
    uncommented = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    uncommented = re.sub(r"//[^\n]*", "", uncommented)
    assert re.search(r"#\s*include\s*[<\"][^>\"]*json\.hpp[>\"]", uncommented), \
        "The C++ source must include the downloaded json.hpp header."
    assert re.search(r"\bnlohmann\b", uncommented), \
        "The C++ source must use the nlohmann/json library."


def test_tracked_artifacts_jsonl():
    jsonl_path = "/home/user/tracked_artifacts.jsonl"
    assert os.path.exists(jsonl_path), f"The file {jsonl_path} is missing."
    assert os.path.isfile(jsonl_path), f"{jsonl_path} is not a file."

    expected_valid_experiments = {
        "EXP_001": {"accuracy": 0.95, "epoch_count": 100, "status": "SUCCESS"},
        "EXP_005": {"accuracy": 0.80, "epoch_count": 10, "status": "FAILED"},
        "EXP_008": {"accuracy": 0.91, "epoch_count": 40, "status": "SUCCESS"},
    }

    parsed_experiments = {}
    with open(jsonl_path, "r") as f:
        for line_num, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                exp_id = obj.get("experiment_id")
                assert exp_id, f"Line {line_num + 1} is missing 'experiment_id'."
                parsed_experiments[exp_id] = {
                    "accuracy": obj.get("accuracy"),
                    "epoch_count": obj.get("epoch_count"),
                    "status": obj.get("status")
                }
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num + 1} in {jsonl_path} is not valid JSON.")

    assert len(parsed_experiments) == len(expected_valid_experiments), \
        f"Expected {len(expected_valid_experiments)} valid experiments, found {len(parsed_experiments)}."

    for exp_id, expected_data in expected_valid_experiments.items():
        assert exp_id in parsed_experiments, f"Expected experiment {exp_id} is missing from {jsonl_path}."
        actual_data = parsed_experiments[exp_id]
        assert abs(actual_data["accuracy"] - expected_data["accuracy"]) < 1e-6, \
            f"Accuracy for {exp_id} does not match expected value."
        assert actual_data["epoch_count"] == expected_data["epoch_count"], \
            f"Epoch count for {exp_id} does not match expected value."
        assert actual_data["status"] == expected_data["status"], \
            f"Status for {exp_id} does not match expected value."


def test_invalid_rows_log():
    log_path = "/home/user/invalid_rows.log"
    assert os.path.exists(log_path), f"The file {log_path} is missing."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    expected_invalid_indices = {1, 2, 3, 5, 6}
    actual_invalid_indices = set()

    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                actual_invalid_indices.add(int(line))
            except ValueError:
                pytest.fail(f"Invalid non-integer value found in {log_path}: {line}")

    assert actual_invalid_indices == expected_invalid_indices, \
        f"Expected invalid rows {expected_invalid_indices}, but got {actual_invalid_indices}."


def test_compile_and_execute_on_generated_input():
    originals = {}
    for path in (CSV_PATH, JSONL_PATH, LOG_PATH):
        if os.path.exists(path) and os.path.isfile(path):
            with open(path, "rb") as f:
                originals[path] = f.read()
        else:
            originals[path] = None

    token = secrets.token_hex(6)
    accuracy_value = (secrets.randbelow(800000) + 100000) / 1000000.0
    accuracy_text = f"{accuracy_value:.6f}"

    cases = [
        ([f"EXP_{token}_LOW", "0.0", "1", "SUCCESS"],
         {"experiment_id": f"EXP_{token}_LOW", "accuracy": 0.0, "epoch_count": 1, "status": "SUCCESS"}),
        ([f"EXP_{token}_HIGH", "1.0", "214", "FAILED"],
         {"experiment_id": f"EXP_{token}_HIGH", "accuracy": 1.0, "epoch_count": 214, "status": "FAILED"}),
        ([f"EXP_{token}_RANDOM", accuracy_text, "37", "SUCCESS"],
         {"experiment_id": f"EXP_{token}_RANDOM", "accuracy": float(accuracy_text), "epoch_count": 37, "status": "SUCCESS"}),
        ([f"TEST_{token}", "0.5", "10", "SUCCESS"], None),
        ([f"EXP_{token}_OVER", "1.0001", "10", "SUCCESS"], None),
        ([f"EXP_{token}_UNDER", "-0.01", "10", "FAILED"], None),
        ([f"EXP_{token}_BADFLOAT", "0.5oops", "10", "SUCCESS"], None),
        ([f"EXP_{token}_TEXTFLOAT", "not_a_number", "10", "SUCCESS"], None),
        ([f"EXP_{token}_ZEROEPOCH", "0.5", "0", "SUCCESS"], None),
        ([f"EXP_{token}_NEGEPOCH", "0.5", "-3", "SUCCESS"], None),
        ([f"EXP_{token}_FLOATEPOCH", "0.5", "2.0", "SUCCESS"], None),
        ([f"EXP_{token}_BADEPOCH", "0.5", "12x", "SUCCESS"], None),
        ([f"EXP_{token}_STATUS", "0.5", "10", "UNKNOWN"], None),
    ]
    secrets.SystemRandom().shuffle(cases)

    expected_valid = [expected for _, expected in cases if expected is not None]
    expected_invalid = [index for index, (_, expected) in enumerate(cases) if expected is None]
    csv_data = "experiment_id,accuracy,epoch_count,status\n" + "\n".join(
        ",".join(fields) for fields, _ in cases
    ) + "\n"

    try:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.write(csv_data)
        for path in (JSONL_PATH, LOG_PATH, BINARY_PATH):
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)

        compile_result = subprocess.run(
            ["g++", "-std=c++11", SOURCE_PATH, "-o", BINARY_PATH],
            cwd="/home/user", text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=60
        )
        assert compile_result.returncode == 0, \
            f"Compilation failed:\n{compile_result.stdout}"
        assert os.path.isfile(BINARY_PATH), "Compilation did not create the required executable."
        assert os.access(BINARY_PATH, os.X_OK), "The compiled processor is not executable."

        run_result = subprocess.run(
            [BINARY_PATH], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert run_result.returncode == 0, \
            f"The compiled processor failed:\n{run_result.stdout}"
        assert os.path.isfile(JSONL_PATH), f"The program did not create {JSONL_PATH}."
        assert os.path.isfile(LOG_PATH), f"The program did not create {LOG_PATH}."

        with open(JSONL_PATH, "r", encoding="utf-8") as f:
            json_lines = f.read().splitlines()
        assert all(line.strip() for line in json_lines), "JSONL output contains blank lines."
        assert len(json_lines) == len(expected_valid), \
            f"Expected {len(expected_valid)} valid output rows, found {len(json_lines)}."

        actual_valid = []
        for line_number, line in enumerate(json_lines, 1):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Generated JSONL line {line_number} is invalid JSON: {exc}")
            assert isinstance(obj, dict), f"JSONL line {line_number} is not an object."
            assert set(obj.keys()) == {"experiment_id", "accuracy", "epoch_count", "status"}, \
                f"JSONL line {line_number} does not contain exactly the required keys."
            assert isinstance(obj["experiment_id"], str)
            assert isinstance(obj["accuracy"], (int, float)) and not isinstance(obj["accuracy"], bool)
            assert isinstance(obj["epoch_count"], int) and not isinstance(obj["epoch_count"], bool)
            assert isinstance(obj["status"], str)
            actual_valid.append(obj)

        for actual, expected in zip(actual_valid, expected_valid):
            assert actual["experiment_id"] == expected["experiment_id"]
            assert abs(actual["accuracy"] - expected["accuracy"]) < 1e-9
            assert actual["epoch_count"] == expected["epoch_count"]
            assert actual["status"] == expected["status"]

        with open(LOG_PATH, "r", encoding="utf-8") as f:
            invalid_lines = f.read().splitlines()
        assert all(line.strip() for line in invalid_lines), "Invalid-row log contains blank lines."
        try:
            actual_invalid = [int(line) for line in invalid_lines]
        except ValueError as exc:
            pytest.fail(f"Invalid-row log contains a non-integer value: {exc}")
        assert actual_invalid == expected_invalid, \
            f"Expected invalid row indices {expected_invalid}, got {actual_invalid}."
    finally:
        for path, content in originals.items():
            if content is None:
                if os.path.lexists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
