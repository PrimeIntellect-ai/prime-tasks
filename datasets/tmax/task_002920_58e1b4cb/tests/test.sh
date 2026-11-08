#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import secrets
import subprocess
import pytest

SOURCE = "/home/user/tracker.cpp"
EXECUTABLE = "/home/user/tracker"
CSV_PATH = "/home/user/experiments.csv"
JSON_PATH = "/home/user/embeddings_log.json"

JSON_NUMBER = re.compile(r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?')
FOUR_DECIMAL = re.compile(r'-?(?:0|[1-9]\d*)\.\d{4}')


def numeric_lexemes_outside_strings(text):
    numbers = []
    i = 0
    while i < len(text):
        if text[i] == '"':
            i += 1
            while i < len(text):
                if text[i] == '\\':
                    i += 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
        elif text[i] == '-' or text[i].isdigit():
            match = JSON_NUMBER.match(text, i)
            assert match is not None, f"Invalid numeric token near offset {i}."
            numbers.append(match.group(0))
            i = match.end()
        else:
            i += 1
    return numbers


def load_and_check_json(expected):
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} does not exist."
    text = open(JSON_PATH, 'r', encoding='utf-8').read()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(data, dict), "The root of the JSON file must be an object/dictionary."
    assert set(data.keys()) == set(expected.keys()), \
        f"Expected keys {set(expected.keys())}, but got {set(data.keys())}."

    for key, wanted in expected.items():
        assert isinstance(data[key], list), f"Value for {key} must be a list."
        assert len(data[key]) == 3, f"Value for {key} must have exactly 3 elements."
        for index, (actual, target) in enumerate(zip(data[key], wanted)):
            assert isinstance(actual, (int, float)) and not isinstance(actual, bool), \
                f"Element {index} of {key} must be a number."
            assert math.isfinite(actual), f"Element {index} of {key} must be finite."
            assert actual == target, \
                f"Mismatch in {key} at index {index}: expected {target:.4f}, got {actual}."

    tokens = numeric_lexemes_outside_strings(text)
    assert len(tokens) == 3 * len(expected), \
        f"Expected {3 * len(expected)} JSON number tokens, found {len(tokens)}."
    for token in tokens:
        assert FOUR_DECIMAL.fullmatch(token), \
            f"JSON number {token!r} is not written with exactly four decimal places."


def expected_for(rows):
    result = {}
    for experiment_id, fields in rows:
        values = [0.0 if field == '' or field == 'NaN' else float(field) for field in fields]
        norm = math.sqrt(sum(value * value for value in values))
        normalized = [0.0, 0.0, 0.0] if norm == 0.0 else [value / norm for value in values]
        result[experiment_id] = [float(f"{value:.4f}") for value in normalized]
    return result


def write_rows(rows):
    with open(CSV_PATH, 'w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['id', 'v1', 'v2', 'v3'])
        for experiment_id, fields in rows:
            writer.writerow([experiment_id] + fields)


def run_and_check(program, rows):
    write_rows(rows)
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    completed = subprocess.run(
        [program], cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert completed.returncode == 0, \
        f"{program} exited with {completed.returncode}. stderr: {completed.stderr}"
    load_and_check_json(expected_for(rows))


def test_tracker_cpp_exists():
    """Verify that the C++ source file exists."""
    assert os.path.isfile(SOURCE), "/home/user/tracker.cpp does not exist."


def test_tracker_executable_exists():
    """Verify that the compiled executable exists."""
    assert os.path.isfile(EXECUTABLE), "/home/user/tracker executable does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/tracker is not executable."
    with open(EXECUTABLE, 'rb') as stream:
        assert stream.read(4) == b'\x7fELF', "/home/user/tracker is not a compiled ELF executable."


def test_embeddings_log_json_exists_and_correct():
    """Verify that the initially generated log contains the required embeddings."""
    expected = {
        "exp_001": [0.6000, 0.8000, 0.0000],
        "exp_002": [0.7071, 0.0000, 0.7071],
        "exp_003": [0.0000, 1.0000, 0.0000],
        "exp_004": [0.0000, 0.0000, 0.0000],
        "exp_005": [0.5774, -0.5774, 0.5774]
    }
    load_and_check_json(expected)


def test_source_and_executable_on_unseen_inputs():
    source_text = open(SOURCE, 'r', encoding='utf-8').read()
    assert re.search(r'#\s*include\s*[<\"](?:eigen3/)?Eigen/', source_text), \
        "tracker.cpp must include Eigen3."
    assert re.search(r'\bEigen\s*::\s*Vector3d\b', source_text), \
        "tracker.cpp must use Eigen::Vector3d."

    rebuilt = "/tmp/tracker_rebuilt"
    compilation = subprocess.run(
        ['g++', '-std=c++17', '-I/usr/include/eigen3', SOURCE, '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compilation.returncode == 0, \
        f"tracker.cpp failed to compile with Eigen3: {compilation.stderr}"

    original_csv = open(CSV_PATH, 'rb').read()
    original_json = open(JSON_PATH, 'rb').read()
    suffix = secrets.token_hex(6)
    a = secrets.randbelow(37) + 2
    b = secrets.randbelow(41) + 3
    c = secrets.randbelow(29) + 2

    executable_rows = [
        (f"zero_{suffix}", ['0.0', '0.0', '0.0']),
        (f"empty_{suffix}", [str(a), '', str(-b)]),
        (f"nan_{suffix}", ['NaN', str(c), str(c)]),
        (f"mixed_{suffix}", [str(-a), str(b), str(c)]),
    ]
    rebuilt_rows = [
        (f"first_{suffix}", [str(b), str(a), '0']),
        (f"missing_{suffix}", ['', 'NaN', str(-c)]),
        (f"negative_{suffix}", [str(-b), str(-a), str(-c)]),
        (f"allzero_{suffix}", ['NaN', '', '0.0']),
    ]

    try:
        run_and_check(EXECUTABLE, executable_rows)
        run_and_check(rebuilt, rebuilt_rows)
    finally:
        with open(CSV_PATH, 'wb') as stream:
            stream.write(original_csv)
        with open(JSON_PATH, 'wb') as stream:
            stream.write(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
