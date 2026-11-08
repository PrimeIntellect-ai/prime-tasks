#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess

RESULT_PATH = "/home/user/result.txt"
SOURCE_PATH = "/home/user/analyze.c"
EXECUTABLE_PATH = "/home/user/analyze"
DATA_PATH = "/home/user/data.csv"


def expected_result(scores):
    n = len(scores)
    mean = sum(scores) / n
    variance = sum((x - mean) ** 2 for x in scores) / (n - 1)
    std_dev = math.sqrt(variance)
    margin_of_error = 1.96 * (std_dev / math.sqrt(n))
    lower_bound = mean - margin_of_error
    upper_bound = mean + margin_of_error
    return f"Mean: {mean:.2f}, CI: [{lower_bound:.2f}, {upper_bound:.2f}]"


def test_result_file_exists():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Expected result file {result_path} is missing."


def test_result_content():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Expected result file {result_path} is missing."

    with open(result_path, "r") as f:
        content = f.read().strip()

    # Calculate expected values based on setup data
    # Group A scores: 10, 20, 30, 40
    scores = [10.0, 20.0, 30.0, 40.0]
    n = len(scores)
    mean = sum(scores) / n
    variance = sum((x - mean) ** 2 for x in scores) / (n - 1)
    std_dev = math.sqrt(variance)
    margin_of_error = 1.96 * (std_dev / math.sqrt(n))

    lower_bound = mean - margin_of_error
    upper_bound = mean + margin_of_error

    expected_string = f"Mean: {mean:.2f}, CI: [{lower_bound:.2f}, {upper_bound:.2f}]"

    assert content == expected_string, f"Content of {result_path} is incorrect. Expected '{expected_string}', got '{content}'."


def test_c_source_and_executable_exist():
    source_path = "/home/user/analyze.c"
    executable_path = "/home/user/analyze"

    assert os.path.isfile(source_path), f"C source file {source_path} is missing."
    assert os.path.isfile(executable_path), f"Executable file {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."


def run_and_check(program, expected):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert completed.returncode == 0, (
        f"{program} exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), f"{program} did not create {RESULT_PATH}."
    with open(RESULT_PATH, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected '{expected}', got '{actual}' from {program}."


def test_program_executes_and_processes_csv():
    mode = os.stat(EXECUTABLE_PATH).st_mode
    assert stat.S_ISREG(mode), f"{EXECUTABLE_PATH} must be a regular compiled executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not an ELF executable."

    rebuilt = "/tmp/analyze_from_submitted_source"
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", rebuilt, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert compile_result.returncode == 0, (
        f"Submitted C source does not compile with -lm: {compile_result.stderr}"
    )

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_result = None
    if os.path.exists(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            original_result = f.read()

    rng = secrets.SystemRandom()
    datasets = []

    # Re-execute against the setup dataset rather than trusting the preexisting result.
    datasets.append((original_data.decode(), [10.0, 20.0, 30.0, 40.0]))

    # Unpredictable datasets prevent a fixed-output implementation from passing.
    for case_index in range(3):
        valid_scores = [float(rng.randrange(-160, 321)) / 4.0 for _ in range(rng.randrange(4, 8))]
        rows = []
        next_id = 1000 + case_index * 100
        for score in valid_scores:
            rows.append(f"{next_id},A,{score}")
            next_id += 1
        rows.extend([
            f"{next_id},A,",
            f"{next_id + 1},B,{rng.randrange(-500, 501) / 2.0}",
            f"{next_id + 2},AA,{rng.randrange(-500, 501) / 2.0}",
            f"{next_id + 3},a,{rng.randrange(-500, 501) / 2.0}",
            f"{next_id + 4},A,",
        ])
        rng.shuffle(rows)
        datasets.append(("id,group,score\n" + "\n".join(rows) + "\n", valid_scores))

    try:
        for csv_content, scores in datasets:
            with open(DATA_PATH, "w") as f:
                f.write(csv_content)
            expected = expected_result(scores)
            run_and_check(EXECUTABLE_PATH, expected)
            run_and_check(rebuilt, expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
