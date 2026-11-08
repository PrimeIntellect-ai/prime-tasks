#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import random
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict

WORKSPACE = "/home/user/workspace"


def test_files_exist():
    workspace = WORKSPACE

    copied_csv = os.path.join(workspace, "sales_wide.csv")
    assert os.path.isfile(copied_csv), f"Expected {copied_csv} to exist (task: copy the file)."

    source_file = os.path.join(workspace, "process.c")
    assert os.path.isfile(source_file), f"Expected C source code at {source_file}."

    executable = os.path.join(workspace, "process")
    assert os.path.isfile(executable), f"Expected compiled executable at {executable}."

    summary_file = os.path.join(workspace, "summary.csv")
    assert os.path.isfile(summary_file), f"Expected output file at {summary_file}."


def test_summary_csv_content():
    staging_csv = "/home/user/staging/sales_wide.csv"
    assert os.path.isfile(staging_csv), f"Original data file {staging_csv} is missing."

    # Recompute the expected output
    sums = defaultdict(int)
    with open(staging_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            region = row['Region']
            for q in ['Q1', 'Q2', 'Q3', 'Q4']:
                val = int(row[q])
                if val >= 0:
                    sums[region] += val

    sorted_sums = sorted(sums.items(), key=lambda x: x[1], reverse=True)

    expected_lines = ["Region,TotalSum"]
    for region, total in sorted_sums:
        expected_lines.append(f"{region},{total}")

    expected_content = "\n".join(expected_lines)

    summary_file = os.path.join(WORKSPACE, "summary.csv")
    with open(summary_file, 'r') as f:
        actual_content = f.read().strip()

    # Normalize line endings
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines_normalized = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines_normalized, (
        "The content of summary.csv does not match the expected aggregated and sorted output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )


def make_case(case_number):
    token = secrets.token_hex(5)
    rows = []
    next_id = 1000 + case_number * 100
    for rank in range(1, 7):
        region = f"R_{token}_{rank}"
        # The large rank component guarantees distinct totals, while the other
        # values exercise multiple rows, zeroes, and ignored negatives.
        rows.append([next_id, region, rank * 10000, rank * 13, -rank * 97, 0])
        next_id += 1
        rows.append([next_id, region, rank * 19, -rank * 31, rank * 23, rank])
        next_id += 1
    random.SystemRandom().shuffle(rows)
    lines = ["ID,Region,Q1,Q2,Q3,Q4"]
    lines.extend(",".join(str(value) for value in row) for row in rows)
    return "\n".join(lines) + "\n"


def expected_for(csv_text):
    sums = defaultdict(int)
    reader = csv.DictReader(csv_text.splitlines())
    for row in reader:
        for quarter in ('Q1', 'Q2', 'Q3', 'Q4'):
            value = int(row[quarter])
            if value >= 0:
                sums[row['Region']] += value
    ordered = sorted(sums.items(), key=lambda item: item[1], reverse=True)
    return ["Region,TotalSum"] + [f"{region},{total}" for region, total in ordered]


def run_case(executable, csv_text):
    input_path = os.path.join(WORKSPACE, "sales_wide.csv")
    output_path = os.path.join(WORKSPACE, "summary.csv")
    with open(input_path, "w", newline="") as f:
        f.write(csv_text)
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        [executable],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed on verifier-provided input with exit code "
        f"{result.returncode}. stderr:\n{result.stderr}"
    )
    assert os.path.isfile(output_path), f"{executable} did not create summary.csv."
    with open(output_path, "r") as f:
        actual = [line.strip() for line in f.read().splitlines() if line.strip()]
    expected = expected_for(csv_text)
    assert actual == expected, (
        f"{executable} produced an incorrect summary for verifier-provided input.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def test_c_source_compiles_and_both_binaries_process_fresh_inputs():
    source = os.path.join(WORKSPACE, "process.c")
    submitted_executable = os.path.join(WORKSPACE, "process")
    input_path = os.path.join(WORKSPACE, "sales_wide.csv")
    output_path = os.path.join(WORKSPACE, "summary.csv")

    assert os.access(submitted_executable, os.X_OK), "process must have executable permissions."
    with open(submitted_executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process must be a compiled ELF executable."

    original_input = open(input_path, "rb").read()
    original_output = open(output_path, "rb").read()

    temp_dir = tempfile.mkdtemp(prefix="verify_c_")
    rebuilt_executable = os.path.join(temp_dir, "process_rebuilt")
    try:
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", rebuilt_executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "process.c did not compile successfully as C.\n"
            f"Compiler output:\n{compile_result.stderr}"
        )

        # Exercise both the submitted compiled artifact and a fresh build of
        # process.c, using inputs generated only when verification runs.
        run_case(submitted_executable, make_case(1))
        run_case(rebuilt_executable, make_case(2))
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        with open(output_path, "wb") as f:
            f.write(original_output)
        shutil.rmtree(temp_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
