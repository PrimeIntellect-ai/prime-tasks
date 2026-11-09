#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile

LIB_PATH = "/home/user/libmath.so"
DB_PATH = "/home/user/data.db"
SCRIPT_PATH = "/home/user/process.py"
LOG_PATH = "/home/user/error.log"


def db_rows():
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute(
            "SELECT id, input_mean, variance FROM records ORDER BY id"
        ).fetchall()


def run_process(data):
    return subprocess.run(
        ["python3", SCRIPT_PATH, "--data", data],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def assert_one_new_row(before, after, expected_mean, expected_variance):
    before_by_id = {row[0]: row for row in before}
    after_by_id = {row[0]: row for row in after}
    assert len(after) == len(before) + 1, "A valid invocation must insert exactly one row."
    for row_id, row in before_by_id.items():
        assert after_by_id.get(row_id) == row, "The script modified or deleted an existing row."
    added = [row for row in after if row[0] not in before_by_id]
    assert len(added) == 1
    _, mean, variance = added[0]
    assert mean is not None and math.isclose(mean, expected_mean, rel_tol=0, abs_tol=1e-6)
    assert variance is not None and math.isclose(
        variance, expected_variance, rel_tol=0, abs_tol=1e-3
    )


def test_libmath_so_exists():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist. Did you compile math_lib.c?"
    assert os.access(LIB_PATH, os.R_OK), f"Cannot read {LIB_PATH}."


def test_sqlite_db_schema_migrated():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    with sqlite3.connect(DB_PATH) as conn:
        columns = {row[1]: row[2] for row in conn.execute("PRAGMA table_info(records);")}
    assert "variance" in columns, "Column 'variance' missing from 'records' table. Schema migration failed."
    assert "REAL" in columns["variance"].upper(), "Column 'variance' should be of type REAL."


def test_sqlite_db_data_inserted():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(
            "SELECT input_mean, variance FROM records WHERE input_mean = 30.0;"
        ).fetchall()
    assert len(rows) > 0, "No record found with input_mean = 30.0. Did the script insert the processed data?"
    found_correct_variance = any(
        row[1] is not None and abs(row[1] - 200.0) < 0.001 for row in rows
    )
    assert found_correct_variance, "Record with input_mean = 30.0 found, but variance is not 200.0."


def test_error_log_exists_and_correct():
    assert os.path.isfile(LOG_PATH), f"Error log file {LOG_PATH} does not exist. Did the script handle invalid input correctly?"
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "INVALID_INPUT", f"Error log content is incorrect. Expected 'INVALID_INPUT', got '{content}'."


def test_process_py_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."


def test_shared_library_executes_correct_algorithm():
    lib = ctypes.CDLL(LIB_PATH)
    func = lib.calc_variance
    func.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.c_int]
    func.restype = ctypes.c_float

    rng = random.SystemRandom()
    cases = [[rng.randint(0, 100) for _ in range(5)] for _ in range(4)]
    cases.append([0, 100, 7, 83, 41])
    for values in cases:
        arr = (ctypes.c_float * len(values))(*values)
        actual = float(func(arr, len(values)))
        mean = sum(values) / len(values)
        expected = sum((value - mean) ** 2 for value in values) / len(values)
        assert math.isclose(actual, expected, rel_tol=0, abs_tol=1e-3), (
            f"calc_variance returned {actual} for {values}; expected {expected}."
        )


def test_process_executes_on_derived_valid_input():
    rng = random.SystemRandom()
    values = [rng.randint(0, 100) for _ in range(5)]
    if values == [10, 20, 30, 40, 50]:
        values[0] = 11
    expected_mean = sum(values) / 5
    expected_variance = sum((v - expected_mean) ** 2 for v in values) / 5

    before = db_rows()
    result = run_process(",".join(map(str, values)))
    assert result.returncode == 0, f"Valid invocation failed: {result.stderr}"
    assert_one_new_row(before, db_rows(), expected_mean, expected_variance)


def test_process_uses_calc_variance_from_shared_library():
    rng = random.SystemRandom()
    values = [rng.randint(0, 100) for _ in range(5)]
    expected_mean = sum(values) / 5
    sentinel = float(rng.randint(4001, 8000)) + 0.25

    tempdir = tempfile.mkdtemp(prefix="verify_libmath_")
    backup = os.path.join(tempdir, "libmath.original.so")
    shim_source = os.path.join(tempdir, "shim.c")
    shim_library = os.path.join(tempdir, "libmath.shim.so")
    shutil.copy2(LIB_PATH, backup)
    try:
        with open(shim_source, "w") as f:
            f.write(
                "float calc_variance(float *arr, int n) { "
                f"(void)arr; (void)n; return {sentinel}f; }}\n"
            )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", shim_source, "-o", shim_library],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        os.replace(shim_library, LIB_PATH)
        before = db_rows()
        result = run_process(",".join(map(str, values)))
        assert result.returncode == 0, f"Invocation with test library failed: {result.stderr}"
        assert_one_new_row(before, db_rows(), expected_mean, sentinel)
    finally:
        os.replace(backup, LIB_PATH)
        shutil.rmtree(tempdir, ignore_errors=True)


def test_validation_on_multiple_inputs():
    invalid_inputs = [
        "150,20",
        "1,2,3,4",
        "1,2,3,4,5,6",
        "-1,2,3,4,5",
        "1,2,3,4,101",
        "1,2,nope,4,5",
        "1,2,3,4,5.0",
    ]
    for data in invalid_inputs:
        before = db_rows()
        if os.path.exists(LOG_PATH):
            os.unlink(LOG_PATH)
        run_process(data)
        assert db_rows() == before, f"Invalid input {data!r} changed the database."
        assert os.path.isfile(LOG_PATH), f"Invalid input {data!r} did not create error.log."
        with open(LOG_PATH, "r") as f:
            content = f.read().strip()
        assert content == "INVALID_INPUT", (
            f"Invalid input {data!r} produced {content!r}, not 'INVALID_INPUT'."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
