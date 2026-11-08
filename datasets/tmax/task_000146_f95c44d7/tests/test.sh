#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import tempfile

SOURCE_PATH = "/home/user/process_data.c"
EXECUTABLE_PATH = "/home/user/etl_parser"
DATA_PATH = "/home/user/data.csv"
RESULT_PATH = "/home/user/etl_result.txt"


def expected_from_file(path):
    valid_count = 0
    max_val = None
    min_val = None

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "value"], "Unexpected header in data.csv"

        for row in reader:
            if len(row) < 2:
                continue
            val_str = row[1].strip()
            if val_str == "" or val_str == "NaN":
                continue
            val = int(val_str)
            valid_count += 1
            if max_val is None or val > max_val:
                max_val = val
            if min_val is None or val < min_val:
                min_val = val

    return (
        f"Valid: {valid_count}\n"
        f"Max: {max_val}\n"
        f"Min: {min_val}\n"
    )


def run_and_check(executable, expected):
    completed = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with status {completed.returncode}.\n"
        f"stderr:\n{completed.stderr}"
    )
    assert completed.stdout == expected, (
        f"Output produced by {executable} is incorrect.\n"
        f"Expected:\n{expected}\n"
        f"Actual:\n{completed.stdout}"
    )


def test_c_source_exists():
    """Check that the C source file exists."""
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."


def test_executable_exists():
    """Check that the compiled executable exists and is executable."""
    assert os.path.exists(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} does not exist."
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not an ELF executable."


def test_result_file_correctness():
    """Check that the result file exists and contains the exact expected metrics."""
    assert os.path.exists(DATA_PATH), f"Input data file {DATA_PATH} is missing."
    assert os.path.exists(RESULT_PATH), f"Output result file {RESULT_PATH} is missing."

    expected_output = expected_from_file(DATA_PATH)
    with open(RESULT_PATH, "r") as f:
        actual_output = f.read().strip() + "\n"

    assert actual_output == expected_output, (
        f"Contents of {RESULT_PATH} do not match the expected output.\n"
        f"Expected:\n{expected_output}\n"
        f"Actual:\n{actual_output}"
    )


def test_source_compiles_and_programs_process_data():
    """Compile the submitted C source and exercise both it and the submitted artifact."""
    original_data = open(DATA_PATH, "rb").read()
    original_result = open(RESULT_PATH, "rb").read() if os.path.exists(RESULT_PATH) else None

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "etl_parser_rebuilt")
        compilation = subprocess.run(
            ["gcc", "-O3", "-Wall", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        assert compilation.returncode == 0, (
            "process_data.c did not compile with gcc -O3 -Wall.\n"
            f"stdout:\n{compilation.stdout}\n"
            f"stderr:\n{compilation.stderr}"
        )

        try:
            expected_original = expected_from_file(DATA_PATH)
            run_and_check(EXECUTABLE_PATH, expected_original)
            run_and_check(rebuilt, expected_original)

            cases = [
                (
                    "id,value\n"
                    "1,NaN\n"
                    "2,\n"
                    "3,0\n"
                    "4,9223372036854775807\n"
                    "5,-9223372036854775808\n"
                    "6,9007199254740993\n"
                    "7,-9007199254740995\n"
                )
            ]

            rng = random.SystemRandom()
            rows = ["id,value\n"]
            for i in range(1, 1501):
                selector = rng.randrange(20)
                if selector == 0:
                    rows.append(f"{i},NaN\n")
                elif selector == 1:
                    rows.append(f"{i},\n")
                else:
                    rows.append(f"{i},{rng.randint(-9223372036854775808, 9223372036854775807)}\n")
            rows.append("1501,9223372036854775806\n")
            rows.append("1502,-9223372036854775807\n")
            cases.append("".join(rows))

            for contents in cases:
                with open(DATA_PATH, "w", newline="") as f:
                    f.write(contents)
                expected = expected_from_file(DATA_PATH)
                run_and_check(EXECUTABLE_PATH, expected)
                run_and_check(rebuilt, expected)
        finally:
            with open(DATA_PATH, "wb") as f:
                f.write(original_data)
            if original_result is not None:
                with open(RESULT_PATH, "wb") as f:
                    f.write(original_result)
            elif os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
