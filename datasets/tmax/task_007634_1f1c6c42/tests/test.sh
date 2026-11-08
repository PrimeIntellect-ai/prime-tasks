#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import sqlite3
import subprocess
import tempfile
from datetime import datetime

import pytest

BASE_DIR = "/home/user/ticket_8832"
SRC_DIR = os.path.join(BASE_DIR, "src")
DB_PATH = os.path.join(BASE_DIR, "db", "results.db")


def test_timeline_log_sorted_and_complete():
    timeline_path = os.path.join(BASE_DIR, "timeline.log")
    assert os.path.isfile(timeline_path), f"File missing: {timeline_path}"

    # Read original logs to get all lines
    logs_dir = os.path.join(BASE_DIR, "logs")
    original_lines = []
    for log_file in ["node_A.log", "node_B.log", "node_C.log"]:
        log_path = os.path.join(logs_dir, log_file)
        if os.path.isfile(log_path):
            with open(log_path, "r") as f:
                original_lines.extend([line.strip() for line in f if line.strip()])

    with open(timeline_path, "r") as f:
        timeline_lines = [line.strip() for line in f if line.strip()]

    # Check completeness
    assert sorted(original_lines) == sorted(timeline_lines), "timeline.log does not contain the exact same lines as the original logs"

    # Check sorting
    timestamps = []
    for line in timeline_lines:
        ts_str = line.split(" ")[0]
        try:
            ts = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
            timestamps.append(ts)
        except ValueError:
            pytest.fail(f"Could not parse timestamp from line: {line}")

    assert timestamps == sorted(timestamps), "timeline.log is not sorted chronologically"


def test_source_code_fixed():
    cpp_path = os.path.join(SRC_DIR, "optimizer.cpp")
    assert os.path.isfile(cpp_path), f"Source file missing: {cpp_path}"

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "short iterations" not in content, "optimizer.cpp still contains 'short iterations' (integer overflow bug)"
    assert "float x" not in content, "optimizer.cpp still contains 'float x' (precision loss bug)"
    assert "float prev_x" not in content, "optimizer.cpp still contains 'float prev_x' (precision loss bug)"


def test_database_has_successful_run():
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check for successful run with input 2500.0
    cursor.execute("SELECT result_value, status FROM convergence_runs WHERE input_value = 2500.0 ORDER BY id DESC LIMIT 1;")
    row = cursor.fetchone()

    assert row is not None, "No run found for input_value = 2500.0 in the database"
    result_value, status = row

    assert status == "SUCCESS", f"Expected status 'SUCCESS' for input 2500.0, got '{status}'"
    assert abs(result_value - 5.0) < 1e-4, f"Expected result_value close to 5.0, got {result_value}"

    conn.close()


def test_final_answer_file():
    answer_path = os.path.join(BASE_DIR, "final_answer.txt")
    assert os.path.isfile(answer_path), f"Final answer file missing: {answer_path}"

    with open(answer_path, "r") as f:
        content = f.read().strip()

    assert content == "5.0000", f"Expected final_answer.txt to contain exactly '5.0000', got '{content}'"


def _run_and_check_new_database_row(executable, input_value):
    conn = sqlite3.connect(DB_PATH)
    before_id = conn.execute("SELECT COALESCE(MAX(id), 0) FROM convergence_runs").fetchone()[0]
    conn.close()

    proc = subprocess.run(
        [executable, format(input_value, ".8f")],
        cwd=SRC_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, (
        f"optimizer failed for input {input_value}: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT input_value, result_value, status FROM convergence_runs WHERE id > ? ORDER BY id",
        (before_id,),
    ).fetchall()
    conn.close()

    assert len(rows) == 1, f"Each optimizer execution must insert exactly one row; got {len(rows)}"
    recorded_input, result_value, status = rows[0]
    assert math.isclose(recorded_input, input_value, rel_tol=0.0, abs_tol=1e-6), (
        f"Executable recorded input {recorded_input}, expected {input_value}"
    )
    assert status == "SUCCESS", f"Expected SUCCESS for input {input_value}, got {status!r}"
    assert result_value is not None and math.isfinite(result_value), "Result must be a finite number"

    # The stationary point of the implemented objective gradient (2*x - 10) is 10/2.
    expected = 10.0 / 2.0
    assert abs(result_value - expected) < 1e-4, (
        f"Incorrect convergence result for input {input_value}: got {result_value}, expected {expected}"
    )


def test_recompiled_artifact_and_algorithm_on_derived_and_unseen_inputs():
    cpp_path = os.path.join(SRC_DIR, "optimizer.cpp")
    service_path = os.path.join(SRC_DIR, "optimizer_service")

    assert os.path.isfile(service_path), "Recompiled optimizer_service is missing"
    assert os.access(service_path, os.X_OK), "optimizer_service is not executable"
    with open(service_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "optimizer_service must be a compiled ELF executable"
    assert os.stat(service_path).st_mtime_ns >= os.stat(cpp_path).st_mtime_ns, (
        "optimizer_service is older than optimizer.cpp; the modified source was not recompiled"
    )

    # Derive the reported failing input from the logs rather than trusting a submitted DB row.
    error_text = ""
    for name in ["node_A.log", "node_B.log", "node_C.log"]:
        with open(os.path.join(BASE_DIR, "logs", name), "r") as f:
            error_text += f.read() + "\n"
    match = re.search(r"\[ERROR\].*?input_value=([-+0-9.eE]+)", error_text)
    assert match, "Could not derive the problematic input from the error logs"
    problematic_input = float(match.group(1))

    # Compile the submitted source independently, so a fabricated executable or DB row cannot pass.
    fd, verification_binary = tempfile.mkstemp(prefix="optimizer_verify_")
    os.close(fd)
    os.unlink(verification_binary)
    try:
        compile_proc = subprocess.run(
            ["g++", "-O2", "-std=c++17", "-o", verification_binary, cpp_path, "-lsqlite3"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_proc.returncode == 0, f"optimizer.cpp does not compile: {compile_proc.stderr}"

        # Exercise both the requested artifact and a verifier-built copy on inputs not known in advance.
        _run_and_check_new_database_row(service_path, problematic_input)
        rng = random.SystemRandom()
        unseen_inputs = [
            float(rng.randint(10000, 90000)) + 0.125,
            float(rng.randint(100000, 900000)) + 0.375,
            float(rng.randint(1000, 9000)) + 0.625,
        ]
        for value in unseen_inputs:
            _run_and_check_new_database_row(verification_binary, value)
    finally:
        if os.path.exists(verification_binary):
            os.unlink(verification_binary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
