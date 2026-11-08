#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import random
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

PROJECT_DIR = "/home/user/math_migrator"
EXPECTED_LINES = [
    "1|3 4 +|7",
    "2|5 6 * 2 +|32",
    "3|1 + + +|0",
    "4|7 8 *|56",
]


@pytest.fixture(scope="session", autouse=True)
def build_and_load_extension():
    makefile = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile), f"Makefile is missing at {makefile}."

    # Remove pre-existing extension binaries so make must really build one.
    for pattern in ("fastmath*.so", "fastmath*.pyd"):
        for path in glob.glob(os.path.join(PROJECT_DIR, pattern)):
            os.remove(path)

    proc = subprocess.run(
        ["make"], cwd=PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert proc.returncode == 0, f"Makefile failed to build the extension:\n{proc.stdout}"

    artifacts = glob.glob(os.path.join(PROJECT_DIR, "fastmath*.so"))
    assert artifacts, "make did not produce a fastmath Python extension."

    probe = subprocess.run(
        [sys.executable, "-c",
         "import fastmath, importlib.machinery; "
         "assert isinstance(fastmath.__loader__, importlib.machinery.ExtensionFileLoader); "
         "print(fastmath.__file__)"],
        cwd=PROJECT_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert probe.returncode == 0, (
        "The built fastmath artifact is not importable as a Python 3 C extension:\n"
        + probe.stderr
    )


def test_success_log_exists_and_correct():
    log_path = os.path.join(PROJECT_DIR, "success.log")
    assert os.path.isfile(log_path), f"success.log is missing at {log_path}."

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == EXPECTED_LINES, (
        f"Contents of success.log do not match expected output.\n"
        f"Expected: {EXPECTED_LINES}\nActual: {actual_lines}"
    )


def test_database_schema_migrated():
    db_path = os.path.join(PROJECT_DIR, "data.db")
    assert os.path.isfile(db_path), f"Database data.db is missing at {db_path}."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(history);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    assert "id" in columns, "Column 'id' missing in 'history' table."
    assert "math_expr" in columns, "Column 'math_expr' missing in 'history' table (migration not applied?)."
    assert "result" in columns, "Column 'result' missing in 'history' table (migration not applied?)."
    assert "equation" not in columns, "Column 'equation' should have been renamed."

    cursor.execute("SELECT id, math_expr, result FROM history ORDER BY id")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        (1, "3 4 +", 7),
        (2, "5 6 * 2 +", 32),
        (3, "1 + + +", 0),
        (4, "7 8 *", 56),
    ]
    assert rows == expected_rows, f"history rows are incorrect: {rows!r}"
    assert [f"{i}|{expr}|{result}" for i, expr, result in rows] == EXPECTED_LINES


def test_c_extension_migrated():
    c_path = os.path.join(PROJECT_DIR, "fastmath.c")
    assert os.path.isfile(c_path), f"fastmath.c is missing at {c_path}."

    with open(c_path, "r") as f:
        content = f.read()

    assert "Py_InitModule" not in content, "fastmath.c still contains Python 2 Py_InitModule."
    assert "PyModuleDef" in content or "PyModule_Create" in content, (
        "fastmath.c does not appear to use the Python 3 PyModuleDef / PyModule_Create API."
    )


def test_c_extension_safety_check():
    c_path = os.path.join(PROJECT_DIR, "fastmath.c")
    assert os.path.isfile(c_path), f"fastmath.c is missing at {c_path}."

    with open(c_path, "r") as f:
        content = f.read()

    assert "< 2" in content or "<2" in content or "<= 1" in content or "<=1" in content, (
        "fastmath.c does not seem to contain an underflow check (e.g., checking if stack pointer < 2)."
    )


def test_compiled_evaluator_on_generated_inputs():
    rng = random.SystemRandom()
    a, b, c, d = [rng.randint(2, 30) for _ in range(4)]
    cases = [
        (f"{a} {b} +", a + b),
        (f"{a} {b} * {c} +", a * b + c),
        (f"{a} {b} + {c} *", (a + b) * c),
        (f"{a} {b} * {c} {d} + +", a * b + c + d),
        (f"{a} +", 0),
        (f"{a} {b} + +", 0),
        (f"{a} * * *", 0),
    ]

    code = (
        "import json, fastmath\n"
        f"cases = {json.dumps(cases)}\n"
        "out = []\n"
        "for expr, expected in cases:\n"
        "    value = fastmath.evaluate_rpn(expr)\n"
        "    assert isinstance(value, int)\n"
        "    out.append(value)\n"
        "print('RESULTS=' + json.dumps(out))\n"
    )
    proc = subprocess.run(
        [sys.executable, "-c", code], cwd=PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert proc.returncode == 0, (
        "fastmath crashed or failed while evaluating valid/underflow inputs:\n"
        + proc.stderr
    )
    marker = [line for line in proc.stdout.splitlines() if line.startswith("RESULTS=")]
    assert marker, f"Evaluator probe produced no results: {proc.stdout!r}"
    actual = json.loads(marker[-1].split("=", 1)[1])
    assert actual == [expected for _, expected in cases]


def test_app_runs_with_python3_and_inserts_generated_results():
    app_path = os.path.join(PROJECT_DIR, "app.py")
    assert os.path.isfile(app_path), f"app.py is missing at {app_path}."

    rng = random.SystemRandom()
    a, b, c, d = [rng.randint(2, 25) for _ in range(4)]
    cases = [
        (f"{a} {b} +", a + b),
        (f"{a} {b} * {c} +", a * b + c),
        (f"{a} + +", 0),
        (f"{c} {d} *", c * d),
    ]

    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy2(app_path, os.path.join(tmp, "app.py"))
        with open(os.path.join(tmp, "input.txt"), "w") as f:
            for expr, _ in cases:
                f.write(expr + "\n")

        db_path = os.path.join(tmp, "data.db")
        conn = sqlite3.connect(db_path)
        conn.execute("CREATE TABLE history (id INTEGER PRIMARY KEY, math_expr TEXT, result INTEGER)")
        conn.commit()
        conn.close()

        env = os.environ.copy()
        env["PYTHONPATH"] = PROJECT_DIR
        proc = subprocess.run(
            [sys.executable, "app.py"], cwd=tmp, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert proc.returncode == 0, (
            "app.py did not run successfully under Python 3 with the migrated schema:\n"
            + proc.stderr
        )

        conn = sqlite3.connect(db_path)
        rows = conn.execute(
            "SELECT id, math_expr, result FROM history ORDER BY id"
        ).fetchall()
        conn.close()

    expected = [(i + 1, expr, result) for i, (expr, result) in enumerate(cases)]
    assert rows == expected, (
        "app.py did not insert both generated expressions and evaluated integer results. "
        f"Expected {expected!r}, got {rows!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
