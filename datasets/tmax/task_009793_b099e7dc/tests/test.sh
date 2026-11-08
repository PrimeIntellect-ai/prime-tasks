#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import uuid
from collections import defaultdict
from pathlib import Path

import pytest

SOURCE = Path("/home/user/analyze_backups.c")
CSV_PATH = Path("/home/user/backup_deps.csv")
OUTPUT_PATH = Path("/home/user/critical_backups.txt")
EXECUTABLE = Path("/tmp/analyze_backups_test")


def expected_output(csv_text):
    out_degrees = defaultdict(int)
    lines = csv_text.strip().splitlines()
    if lines:
        for line in lines[1:]:
            parts = line.split(',')
            if len(parts) >= 1:
                source_db = parts[0].strip()
                out_degrees[source_db] += 1
    sorted_dbs = sorted(out_degrees.items(), key=lambda x: (-x[1], x[0]))
    return "\n".join(f"{db}: {count}" for db, count in sorted_dbs[:3])


def test_c_program_exists():
    """Check that the C program source file exists."""
    assert os.path.isfile(SOURCE), "The C program file /home/user/analyze_backups.c is missing."


def test_output_file_exists():
    """Check that the output text file exists."""
    assert os.path.isfile(OUTPUT_PATH), "The output file /home/user/critical_backups.txt is missing."


def test_output_file_content():
    """Verify the content of the output file matches the expected top 3 databases."""
    assert os.path.isfile(CSV_PATH), "The input CSV file is missing."
    expected_content = expected_output(CSV_PATH.read_text())
    actual_content = OUTPUT_PATH.read_text().strip()
    assert actual_content == expected_content, (
        f"The contents of /home/user/critical_backups.txt are incorrect.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def test_program_compiles_and_generates_results_for_csv_input():
    """Compile and execute the submitted program against original and unseen inputs."""
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", str(SOURCE), "-o", str(EXECUTABLE)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "analyze_backups.c failed to compile with gcc:\n"
        + compile_result.stdout
        + compile_result.stderr
    )
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK)

    original_csv = CSV_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None

    token = uuid.uuid4().hex[:8]
    counts = {
        f"alpha_{token}": 5,
        f"zulu_{token}": 5,
        f"middle_{token}": 4,
        f"lower_{token}": 3,
        f"small_{token}": 2,
    }
    generated_rows = []
    job = 1
    for source, count in counts.items():
        for edge in range(count):
            generated_rows.append(f"{source},target_{token}_{job},job_{job}")
            job += 1
    random.SystemRandom().shuffle(generated_rows)

    fixtures = [
        original_csv.decode(),
        "source_db,target_db,job_id\n"
        "zeta,node1,j1\n"
        "alpha,node2,j2\n"
        "beta,node3,j3\n"
        "zeta,node4,j4\n"
        "gamma,node5,j5\n"
        "alpha,node6,j6\n"
        "beta,node7,j7\n"
        "zeta,node8,j8\n"
        "alpha,node9,j9\n",
        "source_db,target_db,job_id\n" + "\n".join(generated_rows) + "\n",
    ]

    try:
        for csv_text in fixtures:
            CSV_PATH.write_text(csv_text)
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()

            run_result = subprocess.run(
                [str(EXECUTABLE)],
                capture_output=True,
                text=True,
                timeout=10,
                cwd="/home/user",
            )
            assert run_result.returncode == 0, (
                "The compiled program exited unsuccessfully:\n"
                + run_result.stdout
                + run_result.stderr
            )
            assert OUTPUT_PATH.is_file(), (
                "The compiled program did not create /home/user/critical_backups.txt"
            )
            actual = OUTPUT_PATH.read_text().strip()
            expected = expected_output(csv_text)
            assert actual == expected, (
                f"Program produced incorrect output for an exercised CSV input.\n"
                f"Expected:\n{expected}\n\nActual:\n{actual}"
            )
    finally:
        CSV_PATH.write_bytes(original_csv)
        if original_output is None:
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
        else:
            OUTPUT_PATH.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
