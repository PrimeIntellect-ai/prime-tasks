#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

DATA_PATH = "/home/user/data.csv"
OUTPUT_PATH = "/home/user/fixed_output.csv"
SOURCE_PATH = "/home/user/etl_processor.c"
EXE_PATH = "/home/user/etl_processor"
COMPILED_SOURCE_PATH = "/tmp/etl_processor_from_source"


def read_data():
    with open(DATA_PATH, "r") as f:
        data_lines = f.readlines()

    assert len(data_lines) == 10000, "Original data should have 10000 rows."

    data = []
    for line in data_lines:
        if line.strip():
            row = [float(x) for x in line.strip().split(',')]
            assert len(row) == 5, "Each input row must have 5 columns."
            data.append(row)
    assert len(data) == 10000
    return data


def expected_lines(data):
    sums = [0.0] * 5
    for i in range(8000):
        for j in range(5):
            sums[j] += data[i][j]
    means = [s / 8000.0 for s in sums]
    return [
        ",".join(f"{data[i][j] - means[j]:.5f}" for j in range(5))
        for i in range(10000)
    ]


def check_output(data):
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file missing: {OUTPUT_PATH}. Did you run the executable?"
    )

    with open(OUTPUT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_output = expected_lines(data)
    assert len(actual_lines) == 10000, (
        f"Expected 10000 rows in output, got {len(actual_lines)}"
    )

    for i in range(10000):
        assert actual_lines[i] == expected_output[i], (
            f"Mismatch at row {i+1}.\n"
            f"Expected: {expected_output[i]}\n"
            f"Got:      {actual_lines[i]}\n"
            "Ensure you are subtracting the mean of the first 8000 rows from ALL rows, "
            "and formatting as %.5f."
        )


def run_and_check(program):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    check_output(read_data())


def write_generated_data(seed):
    rng = random.Random(seed)
    with open(DATA_PATH, "w") as f:
        for i in range(10000):
            values = []
            for col in range(5):
                base = (-20.0 + col * 3.0) if i < 8000 else (300.0 + col * 17.0)
                value = base + rng.uniform(-7.0, 7.0)
                values.append(f"{value:.5f}")
            f.write(",".join(values) + "\n")


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Missing compiled executable: {EXE_PATH}"
    assert os.access(EXE_PATH, os.X_OK), (
        f"File {EXE_PATH} is not executable. Did you compile it correctly?"
    )
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{EXE_PATH} is not a compiled ELF executable. Compile the fixed C source with gcc."
        )


def test_fixed_output_correctness():
    assert os.path.isfile(SOURCE_PATH), f"Missing C source file: {SOURCE_PATH}"

    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", COMPILED_SOURCE_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        "The submitted C source does not compile with gcc.\n"
        f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
    )

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    try:
        # Preserve the original correctness assertion, but require the submitted
        # executable itself to create the file rather than trusting a prebuilt CSV.
        run_and_check(EXE_PATH)

        # Exercise both the submitted binary and a fresh build of the submitted
        # source on verifier-generated data.
        write_generated_data(9137421)
        run_and_check(EXE_PATH)

        write_generated_data(2846159)
        run_and_check(COMPILED_SOURCE_PATH)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK):
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            subprocess.run(
                [EXE_PATH], cwd="/home/user", stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=30, check=False
            )

    # Ensure the final requested artifact is correct for the restored dataset.
    check_output(read_data())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
