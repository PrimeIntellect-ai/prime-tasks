#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shutil
import stat
import subprocess

DATA_PATH = '/home/user/data.csv'
SOURCE_PATH = '/home/user/process.c'
EXECUTABLE_PATH = '/home/user/process'
OUTPUT_PATH = '/home/user/output.txt'


def expected_output(data):
    magnitudes = []
    for line in data.decode('utf-8').splitlines():
        parts = line.strip().split(',')
        if len(parts) != 5:
            continue
        x_str, y_str, z_str = parts[2], parts[3], parts[4]
        if "NaN" in (x_str, y_str, z_str):
            continue
        x, y, z = float(x_str), float(y_str), float(z_str)
        magnitudes.append(math.sqrt(x*x + y*y + z*z))

    assert len(magnitudes) > 1, "Not enough valid rows to compute sample statistics."
    n = len(magnitudes)
    mean = sum(magnitudes) / n
    variance = sum((m - mean)**2 for m in magnitudes) / (n - 1)
    std_dev = math.sqrt(variance)
    margin = 1.96 * std_dev / math.sqrt(n)
    return f"Mean: {mean:.4f}, CI: [{mean-margin:.4f}, {mean+margin:.4f}]"


def remove_output():
    if os.path.lexists(OUTPUT_PATH):
        assert not os.path.isdir(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."
        os.unlink(OUTPUT_PATH)


def run_and_check(data):
    with open(DATA_PATH, 'wb') as f:
        f.write(data)

    expected = expected_output(data)
    remove_output()
    result = subprocess.run(
        [EXECUTABLE_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled C program exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."
    with open(OUTPUT_PATH, 'r') as f:
        actual = f.read().strip()
    assert actual == expected, (
        f"Output content does not match expected.\n"
        f"Expected: '{expected}'\nGot: '{actual}'"
    )


def generated_dataset(row_count):
    rng = random.SystemRandom()
    lines = []
    for i in range(1, row_count + 1):
        values = [f"{rng.uniform(-25, 25):.4f}" for _ in range(3)]
        if i % 7 == 0:
            values[0] = "NaN"
        elif i % 11 == 0:
            values[1] = "NaN"
        elif i % 13 == 0:
            values[2] = "NaN"
        lines.append(f"{i},verify_{i},{values[0]},{values[1]},{values[2]}\n")
    return ''.join(lines).encode('utf-8')


def test_c_program_and_output():
    assert os.path.exists(DATA_PATH), f"Data file {DATA_PATH} is missing."
    assert os.path.isfile(DATA_PATH), f"Path {DATA_PATH} is not a file."
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    assert os.path.exists(SOURCE_PATH), f"C source file {SOURCE_PATH} does not exist."
    source_stat = os.stat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"Path {SOURCE_PATH} is not a regular file."

    compile_result = subprocess.run(
        ['gcc', SOURCE_PATH, '-o', EXECUTABLE_PATH, '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}.\n"
        f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
    )
    assert os.path.isfile(EXECUTABLE_PATH), "Compilation did not produce an executable file."
    assert os.access(EXECUTABLE_PATH, os.X_OK), "Compiled program is not executable."

    try:
        # Preserve the original verifier's check against the supplied dataset,
        # while ensuring output.txt is freshly produced by the compiled C code.
        run_and_check(original_data)

        # Exercise the same compiled artifact on verifier-generated inputs so a
        # fixed output or a result computed without reading data.csv cannot pass.
        run_and_check(generated_dataset(37))
        run_and_check(generated_dataset(61))
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        if os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK):
            try:
                remove_output()
                subprocess.run(
                    [EXECUTABLE_PATH], cwd='/home/user',
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=10, check=False,
                )
            except Exception:
                pass


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
