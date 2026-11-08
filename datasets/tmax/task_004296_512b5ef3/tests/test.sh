#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import subprocess
import tempfile

C_FILE = "/home/user/prepare_data.c"
SH_FILE = "/home/user/run_pipeline.sh"
RAW_FILE = "/home/user/raw_data.csv"
OUT_FILE = "/home/user/clean_data.csv"
HEADER = "user_id,engagement_score,session_duration,bounce_rate"
OUTPUT_HEADER = ["user_id", "engagement_score", "session_duration", "bounce_rate", "distance"]

ORIGINAL_INPUT = """user_id,engagement_score,session_duration,bounce_rate
1,0.9,400,0.1
2,,1200,0.8
3,0.4,150,0.5
4,0.8,300,0.2
5,,250,0.3
"""

ORIGINAL_EXPECTED = """user_id,engagement_score,session_duration,bounce_rate,distance
1,0.90,400.00,0.10,100.00
2,0.50,1000.00,0.80,700.00
3,0.40,150.00,0.50,150.00
4,0.80,300.00,0.20,0.00
5,0.50,250.00,0.30,50.00"""


def write_raw(rows):
    with open(RAW_FILE, "w", newline="") as f:
        f.write(HEADER + "\n")
        for user_id, engagement, duration, bounce in rows:
            f.write(f"{user_id},{engagement},{duration},{bounce}\n")


def random_rows(count=8):
    rng = secrets.SystemRandom()
    rows = []
    for i in range(count):
        user_id = str(rng.randrange(10000, 99999))
        engagement = "" if i % 3 == 0 else f"{rng.randrange(3, 98) / 100:.2f}"
        if i % 4 == 0:
            duration = f"{rng.randrange(100101, 180000) / 100:.2f}"
        elif i == 1:
            duration = "300.00"
        else:
            duration = f"{rng.randrange(1000, 99000) / 100:.2f}"
        bounce = f"{rng.randrange(1, 99) / 100:.2f}"
        rows.append((user_id, engagement, duration, bounce))
    return rows


def expected_rows(rows):
    expected = []
    for user_id, engagement_text, duration_text, bounce_text in rows:
        engagement = 0.50 if engagement_text == "" else float(engagement_text)
        duration = min(float(duration_text), 1000.0)
        bounce = float(bounce_text)
        distance = math.sqrt(
            (engagement - 0.80) ** 2
            + (duration - 300.0) ** 2
            + (bounce - 0.20) ** 2
        )
        expected.append([
            user_id,
            f"{engagement:.2f}",
            f"{duration:.2f}",
            f"{bounce:.2f}",
            f"{distance:.2f}",
        ])
    return expected


def assert_output(rows):
    assert os.path.exists(OUT_FILE), f"Output file {OUT_FILE} was not created."
    with open(OUT_FILE, newline="") as f:
        actual = list(csv.reader(f))
    assert actual, "Output CSV is empty"
    assert actual[0] == OUTPUT_HEADER, f"Incorrect output header: {actual[0]}"
    assert actual[1:] == expected_rows(rows), (
        f"Processed rows are incorrect.\nExpected: {expected_rows(rows)}\nActual: {actual[1:]}"
    )


def test_01_pipeline_files_exist():
    assert os.path.exists(C_FILE), f"C program file missing at {C_FILE}"
    assert os.path.isfile(C_FILE), f"C program path is not a regular file: {C_FILE}"
    assert os.path.exists(SH_FILE), f"Shell script missing at {SH_FILE}"
    assert os.path.isfile(SH_FILE), f"Shell script path is not a regular file: {SH_FILE}"


def test_02_original_pipeline_output():
    with open(RAW_FILE, "w") as f:
        f.write(ORIGINAL_INPUT)
    os.chmod(SH_FILE, 0o755)
    result = subprocess.run([SH_FILE], capture_output=True, text=True, cwd="/home/user", timeout=20)
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.exists(OUT_FILE), f"Output file {OUT_FILE} was not created by the pipeline."
    with open(OUT_FILE) as f:
        actual_contents = f.read().strip()
    assert actual_contents == ORIGINAL_EXPECTED, (
        f"Contents of {OUT_FILE} do not match the expected output.\n"
        f"Expected:\n{ORIGINAL_EXPECTED}\nActual:\n{actual_contents}"
    )


def test_03_pipeline_handles_unseen_input():
    rows = random_rows()
    write_raw(rows)
    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)
    result = subprocess.run([SH_FILE], capture_output=True, text=True, cwd="/home/user", timeout=20)
    assert result.returncode == 0, (
        f"run_pipeline.sh failed on varied input.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert_output(rows)


def test_04_c_program_itself_handles_unseen_inputs():
    fd, executable = tempfile.mkstemp(prefix="prepare_data_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)
    compile_result = subprocess.run(
        ["gcc", C_FILE, "-o", executable, "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"prepare_data.c did not compile with gcc -lm.\n"
        f"Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
    )
    try:
        for _ in range(3):
            rows = random_rows()
            write_raw(rows)
            if os.path.exists(OUT_FILE):
                os.remove(OUT_FILE)
            result = subprocess.run(
                [executable], capture_output=True, text=True, cwd="/home/user", timeout=10
            )
            assert result.returncode == 0, (
                f"Compiled C program failed on varied input.\n"
                f"Stdout: {result.stdout}\nStderr: {result.stderr}"
            )
            assert_output(rows)
    finally:
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
