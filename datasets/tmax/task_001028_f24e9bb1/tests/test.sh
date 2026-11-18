#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import runpy
import sqlite3
import subprocess
import sys
import tempfile
import types

PROJECT_DIR = "/home/user/project"
DB_PATH = os.path.join(PROJECT_DIR, "db.sqlite3")
MIGRATION_SCRIPT = os.path.join(PROJECT_DIR, "migrate_db.py")
SOLVER_SOURCE = os.path.join(PROJECT_DIR, "solver.c")
SOLUTION_FILE = os.path.join(PROJECT_DIR, "solution.txt")
WS_LOG = os.path.join(PROJECT_DIR, "ws_success.log")
SOLVER_EXE = os.path.join(PROJECT_DIR, "solver")


def get_expected_angle():
    V = 40.0
    g = 9.81
    best_angle = -1

    for theta in range(1, 90):
        rad = math.radians(theta)
        R = (V * V * math.sin(2 * rad)) / g
        H = (V * V * math.sin(rad) * math.sin(rad)) / (2 * g)

        if 99.0 <= R <= 101.0 and H <= 25.0:
            if theta > best_angle:
                best_angle = theta

    return best_angle


def run_and_check_solver(path):
    result = subprocess.run(
        [path], capture_output=True, text=True, timeout=10, check=False
    )
    assert result.returncode == 0, f"Solver exited with {result.returncode}: {result.stderr}"
    assert result.stdout.strip() == str(get_expected_angle()), (
        f"Expected solver to print {get_expected_angle()}, but got {result.stdout!r}."
    )


def test_migration_script_is_python3_and_functional(tmp_path):
    assert os.path.isfile(MIGRATION_SCRIPT), f"Migration script {MIGRATION_SCRIPT} does not exist."

    test_db = tmp_path / "migration_test.sqlite3"
    conn = sqlite3.connect(test_db)
    conn.execute("CREATE TABLE configurations (id INTEGER PRIMARY KEY, name TEXT)")
    conn.execute("INSERT INTO configurations (id, name) VALUES (1, 'stadium_1')")
    conn.commit()
    conn.close()

    real_sqlite3 = sqlite3
    proxy = types.ModuleType("sqlite3")
    proxy.__dict__.update(real_sqlite3.__dict__)

    def redirected_connect(_database, *args, **kwargs):
        return real_sqlite3.connect(str(test_db), *args, **kwargs)

    proxy.connect = redirected_connect
    previous = sys.modules.get("sqlite3")
    sys.modules["sqlite3"] = proxy
    try:
        runpy.run_path(MIGRATION_SCRIPT, run_name="__main__")
    finally:
        if previous is None:
            del sys.modules["sqlite3"]
        else:
            sys.modules["sqlite3"] = previous

    conn = real_sqlite3.connect(test_db)
    columns = [row[1] for row in conn.execute("PRAGMA table_info(configurations)")]
    conn.close()
    assert "max_angle" in columns, "The Python 3 migration script did not add max_angle."


def test_solution_file():
    assert os.path.exists(SOLUTION_FILE), f"Solution file {SOLUTION_FILE} does not exist."
    with open(SOLUTION_FILE, "r") as f:
        content = f.read().strip()

    expected_angle = get_expected_angle()
    assert content == str(expected_angle), f"Expected solution file to contain {expected_angle}, but found '{content}'."


def test_database_updated():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(configurations);")
    columns = [col[1] for col in cursor.fetchall()]
    assert "max_angle" in columns, "The 'max_angle' column was not added to the 'configurations' table."

    cursor.execute("SELECT max_angle FROM configurations WHERE id=1;")
    row = cursor.fetchone()
    assert row is not None, "Row with id=1 does not exist in 'configurations' table."

    expected_angle = get_expected_angle()
    assert row[0] == expected_angle, f"Expected max_angle to be {expected_angle}, but got {row[0]}."

    conn.close()


def test_solver_source_and_make_build():
    assert os.path.isfile(SOLVER_SOURCE), f"Solver source {SOLVER_SOURCE} does not exist."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Makefile")), "Makefile does not exist."

    with tempfile.TemporaryDirectory() as directory:
        independent_solver = os.path.join(directory, "solver_from_source")
        compile_result = subprocess.run(
            ["gcc", SOLVER_SOURCE, "-o", independent_solver, "-lm"],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        assert compile_result.returncode == 0, (
            f"solver.c does not compile: {compile_result.stdout}{compile_result.stderr}"
        )
        run_and_check_solver(independent_solver)

    if os.path.lexists(SOLVER_EXE):
        os.remove(SOLVER_EXE)
    make_result = subprocess.run(
        ["make", "-B", "solver"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    assert make_result.returncode == 0, (
        f"Running make failed: {make_result.stdout}{make_result.stderr}"
    )
    assert os.path.isfile(SOLVER_EXE), "make did not create the solver executable."
    assert os.access(SOLVER_EXE, os.X_OK), "The solver produced by make is not executable."
    with open(SOLVER_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make did not produce a compiled native solver executable."
    run_and_check_solver(SOLVER_EXE)


def test_websocket_success():
    assert os.path.exists(WS_LOG), f"WebSocket success log {WS_LOG} does not exist. Did you send the correct JSON payload?"
    with open(WS_LOG, "r") as f:
        content = f.read().strip()

    expected_angle = get_expected_angle()
    expected_log = f"Received angle: {expected_angle}"
    assert content == expected_log, f"Expected websocket log to be '{expected_log}', but got '{content}'."


def test_c_executable_exists():
    assert os.path.exists(SOLVER_EXE), f"Compiled solver executable {SOLVER_EXE} does not exist."
    assert os.access(SOLVER_EXE, os.X_OK), f"The file {SOLVER_EXE} is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
