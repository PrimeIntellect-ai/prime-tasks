#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import array
import math
import os
import random
import re
import secrets
import struct
import subprocess

SOURCE = "/home/user/profiler_stats.c"
EXECUTABLE = "/home/user/profiler_stats"
OUTPUT = "/home/user/stats_output.txt"
BIN_FILE = "/home/user/execution_times.bin"

OUTPUT_RE = re.compile(
    r"\AEstimated Lambda: (\d+\.\d{5})\n"
    r"Empirical Variance: (\d+\.\d{5})\n"
    r"Analytical Variance: (\d+\.\d{5})(?:\n)?\Z"
)


def expected_values(data):
    n = len(data)
    mean = sum(data) / n
    est_lambda = 1.0 / mean
    sq_diffs = sum((x - mean) ** 2 for x in data)
    emp_var = sq_diffs / (n - 1)
    analyt_var = 1.0 / (est_lambda ** 2)
    return est_lambda, emp_var, analyt_var


def read_and_check_output(expected):
    assert os.path.exists(OUTPUT), f"{OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        text = f.read()

    match = OUTPUT_RE.fullmatch(text)
    assert match is not None, (
        "Output must contain exactly the three required lines, in order, "
        "with each value formatted to exactly 5 decimal places."
    )

    parsed_lambda, parsed_emp_var, parsed_analyt_var = map(float, match.groups())
    est_lambda, emp_var, analyt_var = expected
    tol = 0.00005
    assert abs(parsed_lambda - est_lambda) <= tol, f"Estimated Lambda {parsed_lambda} is not within {tol} of expected {est_lambda:.5f}."
    assert abs(parsed_emp_var - emp_var) <= tol, f"Empirical Variance {parsed_emp_var} is not within {tol} of expected {emp_var:.5f}."
    assert abs(parsed_analyt_var - analyt_var) <= tol, f"Analytical Variance {parsed_analyt_var} is not within {tol} of expected {analyt_var:.5f}."


def run_and_check(program, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    assert result.returncode == 0, f"{program} exited with status {result.returncode}: {result.stderr}"
    read_and_check_output(expected)


def test_profiler_stats_files_exist():
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."
    assert os.path.exists(EXECUTABLE), f"{EXECUTABLE} executable does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_stats_output_correctness():
    assert os.path.exists(BIN_FILE), f"{BIN_FILE} is missing."
    with open(BIN_FILE, "rb") as f:
        data_bytes = f.read()

    num_doubles = len(data_bytes) // 8
    assert len(data_bytes) % 8 == 0
    assert num_doubles == 1000000, "Expected 1,000,000 doubles in the binary file."
    data = struct.unpack(f"{num_doubles}d", data_bytes)
    read_and_check_output(expected_values(data))


def test_program_and_source_compute_from_binary_input():
    rebuilt = "/tmp/profiler_stats_rebuilt"
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"profiler_stats.c does not compile with gcc: {compile_result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    with open(BIN_FILE, "rb") as f:
        original_data = f.read()

    rng = random.Random(secrets.randbits(64))
    values = array.array("d", (0.01 + 2.0 * rng.random() for _ in range(1000000)))
    expected = expected_values(values)

    try:
        with open(BIN_FILE, "wb") as f:
            values.tofile(f)

        # The submitted executable must actually read the current data and create the log.
        run_and_check(EXECUTABLE, expected)
        # Recompiling the submitted source must produce the same working implementation.
        run_and_check(rebuilt, expected)
    finally:
        with open(BIN_FILE, "wb") as f:
            f.write(original_data)
        # Leave the requested output corresponding to the original task data.
        subprocess.run([EXECUTABLE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
