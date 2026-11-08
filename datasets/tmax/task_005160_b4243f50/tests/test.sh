#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import subprocess
import time

import pytest

RAW_PATH = "/home/user/raw_data.csv"
PIPELINE = "/home/user/pipeline"
SOURCE = "/home/user/pipeline.c"
CLEANED = "/home/user/cleaned_data.csv"
SUMMARY = "/home/user/summary.txt"

ORIGINAL_RAW = (
    "id,f1,f2,target\n"
    "1,10,20,0.00\n"
    "2,15,,0.00\n"
    "3,20,30,0.00\n"
    "4,25,NaN,0.00\n"
    "5,30,40,0.00\n"
)


def run_pipeline(executable):
    for path in (CLEANED, SUMMARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started = time.monotonic()
    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    elapsed = time.monotonic() - started
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(CLEANED), f"{executable} did not create {CLEANED}."
    assert os.path.isfile(SUMMARY), f"{executable} did not create {SUMMARY}."
    return elapsed


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_supplied_input():
    with open(RAW_PATH, "w", newline="") as f:
        f.write(ORIGINAL_RAW)
    run_pipeline(PIPELINE)


def test_pipeline_c_exists():
    file_path = "/home/user/pipeline.c"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."


def test_pipeline_executable_exists():
    file_path = "/home/user/pipeline"
    assert os.path.isfile(file_path), f"The executable {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"The file {file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {file_path} is not a compiled ELF executable."


def test_cleaned_data_csv():
    file_path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    expected_content = (
        "id,f1,f2,target\n"
        "1,10,20,17.50\n"
        "2,15,30,26.25\n"
        "3,20,30,27.50\n"
        "4,25,30,28.75\n"
        "5,30,40,37.50"
    )

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of {file_path} does not match the expected final state."


def test_summary_txt():
    file_path = "/home/user/summary.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in {file_path}, but found {len(lines)}."

    assert lines[0] == "Imputed_f2_Mean: 30", f"Line 1 incorrect: {lines[0]}"
    assert lines[1] == "Target_ID_2: 26.25", f"Line 2 incorrect: {lines[1]}"
    assert lines[2] == "Target_ID_4: 28.75", f"Line 3 incorrect: {lines[2]}"

    benchmark_match = re.match(r"^Benchmark_Time_Sec: \d+\.\d{6}$", lines[3])
    assert benchmark_match, f"Line 4 does not match expected format for benchmark time: {lines[3]}"
    assert float(lines[3].split(":", 1)[1]) > 0.0, "Benchmark time must be a positive measured duration."


def validate_generated_outputs(rows, mean, elapsed):
    with open(CLEANED, newline="") as f:
        actual = list(csv.reader(f))

    expected = [["id", "f1", "f2", "target"]]
    targets = {}
    for row_id, f1, f2_text in rows:
        f2 = mean if f2_text in ("", "NaN") else int(f2_text)
        target = 0.25 * f1 + 0.75 * f2
        targets[row_id] = target
        expected.append([str(row_id), str(f1), str(f2), f"{target:.2f}"])

    assert actual == expected, "Pipeline output was not derived correctly from the generated CSV input."

    with open(SUMMARY) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 4
    assert lines[0] == f"Imputed_f2_Mean: {mean}"
    assert lines[1] == f"Target_ID_2: {targets[2]:.2f}"
    assert lines[2] == f"Target_ID_4: {targets[4]:.2f}"
    match = re.fullmatch(r"Benchmark_Time_Sec: (\d+\.\d{6})", lines[3])
    assert match, f"Invalid benchmark line: {lines[3]}"
    reported = float(match.group(1))
    assert reported > 0.0, "Benchmark time must be positive rather than a fixed zero."
    assert reported <= elapsed * 1.5 + 0.05, "Reported benchmark time is not consistent with wall-clock execution."


def test_source_and_executable_process_unseen_input_and_benchmark():
    with open(SOURCE, encoding="utf-8", errors="replace") as f:
        source = f.read()

    assert re.search(r"\b(for|while)\s*\(", source), "pipeline.c does not contain a benchmark loop."
    assert "0.25" in source and "0.75" in source, "pipeline.c does not contain the required inference coefficients."
    assert any(name in source for name in ("clock_gettime", "gettimeofday", "timespec_get", "clock(")), (
        "pipeline.c does not use a timing function."
    )
    compact = re.sub(r"\s+", "", source)
    iteration_forms = (
        "10000000", "10*1000000", "1000000*10", "10000*1000", "1000*10000", "1e7", "1E7"
    )
    assert any(form in compact for form in iteration_forms), "pipeline.c does not specify 10,000,000 benchmark iterations."

    rebuilt = "/tmp/pipeline_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"pipeline.c cannot be compiled by gcc: {compile_result.stderr}"

    rng = random.Random(secrets.randbits(128))
    rows = []
    valid_values = []
    for row_id in range(1, 14):
        f1 = rng.randint(3, 180)
        if row_id in (2, 4, 7):
            f2_text = "" if row_id != 4 else "NaN"
        else:
            value = rng.randint(5, 150)
            valid_values.append(value)
            f2_text = str(value)
        rows.append((row_id, f1, f2_text))
    mean = sum(valid_values) // len(valid_values)

    with open(RAW_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "f1", "f2", "target"])
        for row_id, f1, f2_text in rows:
            writer.writerow([row_id, f1, f2_text, "0.00"])

    elapsed = run_pipeline(PIPELINE)
    validate_generated_outputs(rows, mean, elapsed)

    elapsed = run_pipeline(rebuilt)
    validate_generated_outputs(rows, mean, elapsed)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
