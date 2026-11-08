#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import sqlite3
import subprocess

import pytest

WORKSPACE_DIR = "/home/user/pr_review"
SUCCESS_LOG = "/home/user/ci_success.log"
RUN_CI = os.path.join(WORKSPACE_DIR, "run_ci.sh")
LIB_PATH = os.path.join(WORKSPACE_DIR, "libmath_engine.so")
DB_PATH = os.path.join(WORKSPACE_DIR, "test.db")


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    assert os.path.isfile(RUN_CI), f"CI script {RUN_CI} is missing."
    assert os.access(RUN_CI, os.X_OK), f"CI script {RUN_CI} is not executable."

    for path in (SUCCESS_LOG, LIB_PATH, DB_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [RUN_CI],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"./run_ci.sh failed with exit code {result.returncode}. Output:\n{result.stdout}"
    )


def test_ci_success_log_exists():
    assert os.path.isfile(SUCCESS_LOG), (
        f"The CI success log {SUCCESS_LOG} does not exist. "
        "Did you run ./run_ci.sh successfully?"
    )


def test_ci_success_log_content():
    with open(SUCCESS_LOG, "r") as f:
        content = f.read().strip()
    assert content == "CI PASS", (
        f"Expected {SUCCESS_LOG} to contain exactly 'CI PASS', but got '{content}'."
    )


def test_c_code_bounds_error_fixed():
    c_file = os.path.join(WORKSPACE_DIR, "math_engine.c")
    assert os.path.isfile(c_file), f"File {c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "i <= len" not in content, (
        "The off-by-one bounds error (i <= len) is still present in math_engine.c."
    )


def test_makefile_has_math_lib_linked():
    makefile_path = os.path.join(WORKSPACE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"File {makefile_path} is missing."
    with open(makefile_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "-lm" in content, (
        "The Makefile is still missing the '-lm' flag required to link the math library."
    )


def test_makefile_rebuilds_loadable_math_library_and_computes_correctly():
    try:
        os.remove(LIB_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["make"],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}"
    assert os.path.isfile(LIB_PATH), "make did not create libmath_engine.so"

    dynamic = subprocess.run(
        ["readelf", "-d", LIB_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert dynamic.returncode == 0, f"libmath_engine.so is not a valid shared object:\n{dynamic.stdout}"
    assert "Shared library: [libm.so" in dynamic.stdout, (
        "The rebuilt shared library does not record libm as a runtime dependency."
    )

    lib = ctypes.CDLL(LIB_PATH)
    func = lib.calculate_stddev
    func.restype = ctypes.c_double
    func.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]

    cases = [
        [2.0, 4.0, 4.0, 4.5],
        [-7.5, 1.25, 9.0],
        [3.0, 3.0, 3.0, 3.0, 3.0],
        [0.125, -2.5, 8.75, 4.0, -1.0, 6.5],
    ]
    for values in cases:
        n = len(values)
        # The explicit extra sentinel makes an i <= len over-read deterministic.
        storage = (ctypes.c_double * (n + 1))(*(values + [1234567.0]))
        actual = func(ctypes.cast(storage, ctypes.POINTER(ctypes.c_double)), n)
        mean = math.fsum(values) / n
        expected = math.sqrt(math.fsum((x - mean) ** 2 for x in values) / n)
        assert math.isfinite(actual)
        assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12), (
            f"calculate_stddev returned {actual} for {values}; expected {expected}"
        )


def test_schema_v2_has_alter_table():
    schema_v2_path = os.path.join(WORKSPACE_DIR, "schema_v2.sql")
    assert os.path.isfile(schema_v2_path), f"File {schema_v2_path} is missing."
    with open(schema_v2_path, "r") as f:
        content = f.read().upper()

    # Preserve the original source-level assertion.
    assert "ALTER TABLE" in content and "ADD" in content and "VARIANCE" in content, (
        "schema_v2.sql does not appear to contain a valid ALTER TABLE statement adding the variance column."
    )


def test_schema_migrations_execute_and_add_real_variance_column():
    schema_v1_path = os.path.join(WORKSPACE_DIR, "schema_v1.sql")
    schema_v2_path = os.path.join(WORKSPACE_DIR, "schema_v2.sql")
    assert os.path.isfile(schema_v1_path)
    assert os.path.isfile(schema_v2_path)

    with open(schema_v1_path, "r") as f:
        schema_v1 = f.read()
    with open(schema_v2_path, "r") as f:
        schema_v2 = f.read()

    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(schema_v1)
        conn.executescript(schema_v2)
        columns = conn.execute("PRAGMA table_info(stats)").fetchall()
        variance = [column for column in columns if column[1] == "variance"]
        assert len(variance) == 1, "Migration did not add exactly one variance column."
        assert variance[0][2].upper() == "REAL", (
            f"variance has type {variance[0][2]!r}, expected REAL"
        )
        conn.execute("INSERT INTO stats (mean, variance) VALUES (?, ?)", (3.5, 1.25))
        conn.commit()
    finally:
        conn.close()


def test_sqlite_database_schema():
    db_path = os.path.join(WORKSPACE_DIR, "test.db")
    assert os.path.isfile(db_path), (
        f"Database file {db_path} is missing. The CI script may have failed to run or complete."
    )

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(stats);")
    columns = cursor.fetchall()
    conn.close()

    # Preserve the original generated-database assertion.
    col_names = [col[1] for col in columns]
    assert "variance" in col_names, (
        "The 'variance' column was not found in the 'stats' table. "
        "The schema migration failed or was incorrect."
    )

    variance_columns = [col for col in columns if col[1] == "variance"]
    assert len(variance_columns) == 1
    assert variance_columns[0][2].upper() == "REAL", (
        "The generated database's variance column is not declared REAL."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
