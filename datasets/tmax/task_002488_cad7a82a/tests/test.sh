#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import pytest

SOURCE_PATH = "/home/user/validate_int.cpp"
EXECUTABLE_PATH = "/home/user/validate_int"
OUTPUT_PATH = "/home/user/invalid_rows.txt"


def test_cpp_source_exists():
    assert os.path.isfile(SOURCE_PATH), "The C++ source file /home/user/validate_int.cpp is missing."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"The executable {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"The file {EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted executable is not a compiled ELF binary."


def test_invalid_rows_output():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = ["4", "5", "6", "8", "11", "12"]
    assert content == expected_lines, (
        f"The contents of {OUTPUT_PATH} do not match the expected invalid row numbers. "
        f"Expected: {expected_lines}, but got: {content}"
    )


def run_validator(executable, csv_path, column):
    result = subprocess.run(
        [str(executable), str(csv_path), str(column)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.stdout.strip().splitlines()


def test_executable_behavior(tmp_path):
    # Preserve the original behavioral check.
    dummy_csv = tmp_path / "dummy.csv"
    dummy_csv.write_text(
        "header1,header2\n"
        "1,10\n"
        "2,10.5\n"
        "3,-20\n"
        "4,NaN\n"
        "5,\n"
        "6,-\n"
        "7,abc\n"
    )

    output_lines = run_validator(EXECUTABLE_PATH, dummy_csv, 1)
    expected_output = ["3", "5", "6", "7", "8"]
    assert output_lines == expected_output, (
        "The compiled executable did not produce the correct output on a test dataset. "
        f"Expected: {expected_output}, but got: {output_lines}"
    )


@pytest.fixture(scope="session")
def rebuilt_executable(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "validate_int_rebuilt"
    result = subprocess.run(
        ["g++", "-O3", SOURCE_PATH, "-o", str(output)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"validate_int.cpp failed to compile with g++ -O3:\n{result.stderr}"
    return output


def random_digits(rng):
    length = rng.randint(1, 14)
    return "".join(str(rng.randrange(10)) for _ in range(length))


def make_dynamic_case(path, rng, case_number):
    column_count = rng.randint(2, 7)
    target_column = rng.randrange(column_count)
    header = [f"field_{case_number}_{i}" for i in range(column_count)]

    valid_values = [
        random_digits(rng),
        "-" + random_digits(rng),
        "0",
        "-0",
        "0" * rng.randint(2, 8) + random_digits(rng),
    ]
    invalid_values = [
        "",
        "-",
        random_digits(rng) + ".0",
        "NaN",
        " " + random_digits(rng),
        random_digits(rng) + " ",
        "+" + random_digits(rng),
        "--" + random_digits(rng),
        random_digits(rng) + "x",
        "3.14",
    ]

    labels = [True] * rng.randint(8, 15) + [False] * rng.randint(10, 18)
    rng.shuffle(labels)
    rows = []
    expected = []

    for data_index, is_valid in enumerate(labels):
        row = [random_digits(rng) for _ in range(column_count)]
        if is_valid:
            row[target_column] = rng.choice(valid_values)
        else:
            row[target_column] = rng.choice(invalid_values)
            expected.append(str(data_index + 2))
        rows.append(",".join(row))

    path.write_text(",".join(header) + "\n" + "\n".join(rows) + "\n")
    return target_column, expected


def test_randomized_csv_validation(tmp_path, rebuilt_executable):
    # Inputs and row positions are chosen at verification time, so fixed-output
    # executables cannot satisfy this check.
    rng = secrets.SystemRandom()
    cases = []
    for case_number in range(7):
        csv_path = tmp_path / f"generated_{secrets.token_hex(8)}.csv"
        column, expected = make_dynamic_case(csv_path, rng, case_number)
        cases.append((csv_path, column, expected))

    # Exercise both the submitted binary and a fresh g++ -O3 build of the source.
    for executable in (EXECUTABLE_PATH, rebuilt_executable):
        for csv_path, column, expected in cases:
            actual = run_validator(executable, csv_path, column)
            assert actual == expected, (
                f"{executable} produced incorrect output for column {column} of a generated CSV. "
                f"Expected {expected}, got {actual}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
