#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

OPTIMIZER = "/home/user/optimizer.py"
ENV_PATH = "/home/user/.env"
DUMP_PATH = "/home/user/service_mem.dump"
DB_PATH = "/home/user/data.db"
SOLUTION_PATH = "/home/user/solution.txt"


def calculate(values, rate=0.15):
    val = sum(values)
    target = 100.0
    iterations = 0
    while abs(val - target) > 0.1:
        val += (target - val) * rate
        iterations += 1
        if iterations > 1000:
            pytest.fail("Convergence calculation exceeded iteration limit during test verification.")
    return f"{val:.2f}"


def read_valid_rate_assignment():
    assert os.path.isfile(ENV_PATH), f"Environment file {ENV_PATH} is missing."
    with open(ENV_PATH, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assignments = []
    for line in lines:
        match = re.fullmatch(r"CONVERGENCE_RATE=([+-]?(?:\d+(?:\.\d*)?|\.\d+))", line)
        if match:
            assignments.append(match.group(1))

    assert len(assignments) == 1, ".env must contain exactly one valid CONVERGENCE_RATE=<number> assignment."
    return assignments[0]


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_optimizer():
    assert os.path.exists(OPTIMIZER), f"Optimizer script {OPTIMIZER} is missing."
    mode = os.lstat(OPTIMIZER).st_mode
    assert stat.S_ISREG(mode), f"Optimizer artifact {OPTIMIZER} must be a regular file."

    rate_text = read_valid_rate_assignment()
    assert float(rate_text) == 0.15, "CONVERGENCE_RATE must be 0.15."
    with open(DUMP_PATH, "rb") as f:
        dump = f.read()
    marker = b"CRITICAL_ENV_VAR:CONVERGENCE_RATE=" + rate_text.encode("ascii")
    assert marker in dump, "The configured convergence rate was not found in the memory dump marker."

    if os.path.lexists(SOLUTION_PATH):
        os.unlink(SOLUTION_PATH)

    result = subprocess.run(
        ["python3", OPTIMIZER],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Running optimizer.py failed:\n{result.stdout}"
    assert os.path.isfile(SOLUTION_PATH), "optimizer.py did not create /home/user/solution.txt."
    with open(SOLUTION_PATH, "rb") as f:
        original_solution = f.read()

    # Exercise the repaired query and calculation against another compatible DB.
    # A submission which merely writes the known answer for the original DB will fail.
    with tempfile.TemporaryDirectory() as tmpdir:
        db_backup = os.path.join(tmpdir, "data.db")
        shutil.copy2(DB_PATH, db_backup)
        try:
            os.unlink(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute("CREATE TABLE metrics (id INTEGER PRIMARY KEY, value REAL, status TEXT)")
            c.execute("INSERT INTO metrics (value, status) VALUES (?, ?)", (4.0, "Active"))
            c.execute("INSERT INTO metrics (value, status) VALUES (?, ?)", (6.0, "Active"))
            c.execute("INSERT INTO metrics (value, status) VALUES (?, ?)", (999.0, "Inactive"))
            conn.commit()
            conn.close()

            if os.path.lexists(SOLUTION_PATH):
                os.unlink(SOLUTION_PATH)
            variant = subprocess.run(
                ["python3", OPTIMIZER],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
            )
            assert variant.returncode == 0, f"optimizer.py failed on a compatible test database:\n{variant.stdout}"
            assert os.path.isfile(SOLUTION_PATH), "optimizer.py did not produce a solution for the test database."
            with open(SOLUTION_PATH, "r", encoding="utf-8") as f:
                variant_content = f.read().strip()
            assert variant_content == calculate([4.0, 6.0]), "optimizer.py does not calculate its result from active database rows."
        finally:
            if os.path.lexists(DB_PATH):
                os.unlink(DB_PATH)
            shutil.copy2(db_backup, DB_PATH)
            with open(SOLUTION_PATH, "wb") as f:
                f.write(original_solution)


def test_solution_file_correct():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"Solution file {solution_path} does not exist. Did you run the optimizer script?"

    with open(solution_path, 'r') as f:
        content = f.read().strip()

    # Calculate the expected value dynamically based on the DB and correct rate
    db_path = "/home/user/data.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT value FROM metrics WHERE status = 'Active'")
    rows = c.fetchall()
    conn.close()

    val = sum(r[0] for r in rows)
    target = 100.0
    rate = 0.15

    iterations = 0
    while abs(val - target) > 0.1:
        val += (target - val) * rate
        iterations += 1
        if iterations > 1000:
            pytest.fail("Convergence calculation exceeded iteration limit during test verification.")

    expected_val = f"{val:.2f}"

    assert content == expected_val, f"Expected solution '{expected_val}', but got '{content}'. Ensure the convergence logic and database query are correct."


def test_env_file_updated():
    env_path = "/home/user/.env"
    assert os.path.isfile(env_path), f"Environment file {env_path} is missing."

    with open(env_path, 'r') as f:
        content = f.read()

    assert "0.15" in content, "The .env file does not appear to contain the correct CONVERGENCE_RATE extracted from the memory dump."
    assert read_valid_rate_assignment() == "0.15", "The .env file must contain a valid CONVERGENCE_RATE=0.15 assignment."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
