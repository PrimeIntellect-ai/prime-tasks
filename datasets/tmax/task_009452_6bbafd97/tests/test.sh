#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

DATA_PATH = "/home/user/data.csv"
PROCESS_PATH = "/home/user/process"
OUTPUT_PATHS = [
    "/home/user/train_scaled.csv",
    "/home/user/test_scaled.csv",
    "/home/user/stats.txt",
]

CANONICAL_DATA = """f1,f2
10.0,20.0
12.0,22.0
14.0,24.0
16.0,26.0
18.0,28.0
"""


def write_data(rows=None):
    with open(DATA_PATH, "w") as f:
        if rows is None:
            f.write(CANONICAL_DATA)
        else:
            f.write("f1,f2\n")
            for a, b in rows:
                f.write(f"{a:.1f},{b:.1f}\n")


def run_program(executable):
    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    for path in OUTPUT_PATHS:
        assert os.path.isfile(path), f"Program did not generate {path}"


def test_executable_exists():
    assert os.path.isfile(PROCESS_PATH), f"Missing compiled executable: {PROCESS_PATH}"
    assert os.access(PROCESS_PATH, os.X_OK), f"The file {PROCESS_PATH} is not executable."
    with open(PROCESS_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process is not a compiled ELF executable"

    write_data()
    run_program(PROCESS_PATH)


def test_stats_txt():
    stats_path = "/home/user/stats.txt"
    assert os.path.isfile(stats_path), f"Missing file: {stats_path}"

    with open(stats_path, "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) == 2, f"Expected 2 lines in {stats_path}, got {len(content)}"

    expected_f1 = "f1: mean=15.6000, std=2.9394"
    expected_f2 = "f2: mean=25.6000, std=2.9394"

    assert expected_f1 in content[0], f"Line 1 of stats.txt is incorrect. Expected to contain '{expected_f1}', got '{content[0]}'"
    assert expected_f2 in content[1], f"Line 2 of stats.txt is incorrect. Expected to contain '{expected_f2}', got '{content[1]}'"


def test_test_scaled_csv():
    test_scaled_path = "/home/user/test_scaled.csv"
    assert os.path.isfile(test_scaled_path), f"Missing file: {test_scaled_path}"

    with open(test_scaled_path, "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) == 3, f"Expected 3 lines (header + 2 rows) in {test_scaled_path}, got {len(content)}"
    assert content[0].strip() == "f1,f2", "Header in test_scaled.csv is incorrect."

    expected_row1 = "-1.2247,-1.2247"
    expected_row2 = "-0.5443,-0.5443"

    assert content[1].strip() == expected_row1, f"Row 1 of test_scaled.csv is incorrect. Expected '{expected_row1}', got '{content[1]}'"
    assert content[2].strip() == expected_row2, f"Row 2 of test_scaled.csv is incorrect. Expected '{expected_row2}', got '{content[2]}'"


def test_train_scaled_csv():
    train_scaled_path = "/home/user/train_scaled.csv"
    assert os.path.isfile(train_scaled_path), f"Missing file: {train_scaled_path}"

    with open(train_scaled_path, "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) == 6, f"Expected 6 lines (header + 5 rows) in {train_scaled_path}, got {len(content)}"
    assert content[0].strip() == "f1,f2", "Header in train_scaled.csv is incorrect."

    expected_rows = [
        "0.1361,0.1361",
        "0.8165,0.8165",
        "-1.9052,-1.9052",
        "0.1361,0.1361",
        "0.8165,0.8165"
    ]

    for i in range(5):
        actual = content[i+1].strip()
        expected = expected_rows[i]
        assert actual == expected, f"Row {i+1} of train_scaled.csv is incorrect. Expected '{expected}', got '{actual}'"


def xorshift_indices():
    state = 42
    result = []
    for _ in range(5):
        state ^= (state << 13) & 0xffffffff
        state &= 0xffffffff
        state ^= state >> 17
        state &= 0xffffffff
        state ^= (state << 5) & 0xffffffff
        state &= 0xffffffff
        result.append(state % 5)
    return result


def expected_for(rows):
    indices = xorshift_indices()
    means = []
    stds = []
    for column in range(2):
        sampled = [rows[i][column] for i in indices]
        mean = sum(sampled) / 5.0
        variance = sum((value - mean) * (value - mean) for value in sampled) / 5.0
        means.append(mean)
        stds.append(math.sqrt(variance))

    train = [
        tuple((rows[index][j] - means[j]) / stds[j] for j in range(2))
        for index in indices
    ]
    selected = set(indices)
    test = [
        tuple((rows[i][j] - means[j]) / stds[j] for j in range(2))
        for i in range(5) if i not in selected
    ]
    return means, stds, train, test


def read_csv(path, expected_rows):
    with open(path, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) == expected_rows + 1, f"Wrong number of lines in {path}: {lines}"
    assert lines[0].strip() == "f1,f2"
    result = []
    for line in lines[1:]:
        fields = line.strip().split(',')
        assert len(fields) == 2, f"Malformed row in {path}: {line}"
        values = tuple(float(field) for field in fields)
        assert all(math.isfinite(value) for value in values)
        result.append(values)
    return result


def assert_close_rows(actual, expected):
    assert len(actual) == len(expected)
    for actual_row, expected_row in zip(actual, expected):
        for actual_value, expected_value in zip(actual_row, expected_row):
            assert abs(actual_value - expected_value) <= 0.00006, (
                f"Expected {expected_value:.4f}, got {actual_value:.4f}"
            )


def validate_dynamic_outputs(rows):
    means, stds, expected_train, expected_test = expected_for(rows)

    with open("/home/user/stats.txt", "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) == 2
    pattern = re.compile(r"^f([12]): mean=([-+0-9.eE]+), std=([-+0-9.eE]+)$")
    for j, line in enumerate(lines):
        match = pattern.fullmatch(line.strip())
        assert match, f"Malformed stats line: {line}"
        assert int(match.group(1)) == j + 1
        actual_mean = float(match.group(2))
        actual_std = float(match.group(3))
        assert math.isfinite(actual_mean) and math.isfinite(actual_std)
        assert abs(actual_mean - means[j]) <= 0.00006
        assert abs(actual_std - stds[j]) <= 0.00006

    actual_train = read_csv("/home/user/train_scaled.csv", len(expected_train))
    actual_test = read_csv("/home/user/test_scaled.csv", len(expected_test))
    assert_close_rows(actual_train, expected_train)
    assert_close_rows(actual_test, expected_test)


def test_program_and_source_on_unseen_data():
    compiled_from_source = "/tmp/process_from_submitted_source"
    result = subprocess.run(
        ["gcc", "/home/user/process.c", "-o", compiled_from_source, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, f"Submitted process.c does not compile: {result.stderr}"

    rng = random.SystemRandom()
    datasets = []
    while len(datasets) < 3:
        rows = [
            (rng.randrange(-1000, 1001) / 10.0, rng.randrange(-1000, 1001) / 10.0)
            for _ in range(5)
        ]
        _, stds, _, _ = expected_for(rows)
        if min(stds) > 0.1:
            datasets.append(rows)

    try:
        for executable in (PROCESS_PATH, compiled_from_source):
            for rows in datasets:
                write_data(rows)
                run_program(executable)
                validate_dynamic_outputs(rows)
    finally:
        write_data()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
