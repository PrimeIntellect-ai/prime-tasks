#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import ctypes
import math
import os
import random
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

LIB_DIR = "/app/fast-calc-2.1.0"
SO_PATH = os.path.join(LIB_DIR, "libfastcalc.so")
SANITIZER = "/home/user/sanitizer"
SANITIZER_SOURCE = "/home/user/sanitizer.c"
DB_PATH = "/home/user/math_data.db"


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, text=True, **kwargs)


def test_stage1_libfastcalc_built_by_makefile():
    assert os.path.isfile(os.path.join(LIB_DIR, "Makefile")), "Vendored Makefile is missing."

    subprocess.run(["make", "clean"], cwd=LIB_DIR, capture_output=True, text=True)
    for name in ("libfastcalc.so", "fast_calc.o", "fast_math.o"):
        path = os.path.join(LIB_DIR, name)
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(["make"], cwd=LIB_DIR, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"The repaired Makefile failed to build:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} is missing."
    assert os.path.isfile(os.path.join(LIB_DIR, "fast_math.o")), "The assembly object fast_math.o was not built."

    obj_symbols = run_checked(["nm", os.path.join(LIB_DIR, "fast_math.o")]).stdout
    assert re.search(r"\bfast_add\b", obj_symbols), "fast_math.S did not produce fast_add in fast_math.o."

    dynamic = run_checked(["readelf", "-d", SO_PATH]).stdout
    assert re.search(r"Shared library: \[libm\.so", dynamic), "libfastcalc.so is not linked against libm."

    try:
        lib = ctypes.CDLL(SO_PATH)
    except Exception as exc:
        pytest.fail(f"Failed to load {SO_PATH}: {exc}")

    assert hasattr(lib, "calculate"), "Shared library does not export calculate."
    assert hasattr(lib, "fast_add"), "Shared library does not export the assembly routine fast_add."

    lib.calculate.argtypes = [ctypes.c_double, ctypes.c_double]
    lib.calculate.restype = ctypes.c_double
    for a, b in ((0.0, 0.0), (0.4, -1.2), (2.3, 4.1)):
        actual = lib.calculate(a, b)
        expected = math.sin(a) + math.cos(b)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)

    lib.fast_add.argtypes = [ctypes.c_long, ctypes.c_long]
    lib.fast_add.restype = ctypes.c_long
    for a, b in ((2, 3), (-17, 9), (1234567, 7654321)):
        assert lib.fast_add(a, b) == a + b


def sanitizer_output(path, expression):
    result = subprocess.run([path, expression], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"Sanitizer exited with {result.returncode} for {expression!r}."
    assert result.stdout in ("ACCEPT", "ACCEPT\n", "REJECT", "REJECT\n"), (
        f"Sanitizer output must be strictly ACCEPT or REJECT, got {result.stdout!r}."
    )
    return result.stdout.strip()


def generated_corpus():
    rng = random.SystemRandom()
    clean = [
        "3 + (4 * 2)", "100 / 2.5", "((1+2)*(3-4))", "1-(2-(3-(4-(5))))",
        "(1+(2+(3+(4+5))))", "42", "-7 + 3", "8 / (2 + 2)",
    ]
    evil = [
        "((((((1))))))", "1 % 2", "3 & 1", "4 | 2", "8 ^ 3",
        "10 / 0", "10/0.0", "7 / 00.000", "1+(2+(3+(4+(5+(6)))))",
    ]

    operators = ["+", "-", "*", "/"]
    for _ in range(30):
        values = [str(rng.randint(1, 999)) for _ in range(4)]
        ops = [rng.choice(operators) for _ in range(3)]
        clean.append(f"({values[0]} {ops[0]} ({values[1]} {ops[1]} ({values[2]} {ops[2]} {values[3]})))")

        value = rng.randint(1, 999)
        depth = rng.randint(6, 10)
        evil.append("(" * depth + str(value) + ")" * depth)
        evil.append(f"{rng.randint(1,999)} {rng.choice(['%', '&', '|', '^'])} {rng.randint(1,999)}")
        zero = rng.choice(["0", "0.0", "00.00", "000.0000"])
        evil.append(f"{rng.randint(1,999)} /   {zero}")
    return clean, evil


def test_stage2_sanitizer_source_and_executable():
    assert os.path.isfile(SANITIZER_SOURCE), f"Sanitizer source {SANITIZER_SOURCE} is missing."
    assert os.path.isfile(SANITIZER), f"Sanitizer executable {SANITIZER} is missing."
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer {SANITIZER} is not executable."

    rebuilt = "/tmp/sanitizer_from_source"
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", SANITIZER_SOURCE, "-o", rebuilt],
        capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0, f"sanitizer.c does not compile:\n{result.stdout}\n{result.stderr}"

    clean, evil = generated_corpus()
    for executable in (SANITIZER, rebuilt):
        for expression in clean:
            assert sanitizer_output(executable, expression) == "ACCEPT", expression
        for expression in evil:
            assert sanitizer_output(executable, expression) == "REJECT", expression


def python_is_valid(expr):
    depth = 0
    for char in expr:
        if char == '(':
            depth += 1
            if depth > 5:
                return False
        elif char == ')':
            depth -= 1
    if any(char in expr for char in "%&|^"):
        return False
    if re.search(r"/\s*0+(\.0+)?\b", expr):
        return False
    return True


def assert_migrated_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='equations_v2'")
        assert cursor.fetchone() is not None, "Table equations_v2 does not exist."

        cursor.execute("PRAGMA table_info(equations_v2)")
        columns = [(row[1], row[2].upper(), row[5]) for row in cursor.fetchall()]
        assert columns == [
            ("id", "INTEGER", 1), ("expression", "TEXT", 0), ("status", "TEXT", 0)
        ], f"Incorrect equations_v2 schema: {columns}"

        cursor.execute("SELECT id, expression FROM equations_v1")
        v1_rows = cursor.fetchall()
        cursor.execute("SELECT id, expression, status FROM equations_v2")
        v2_rows = cursor.fetchall()
    finally:
        conn.close()

    assert len(v2_rows) == len(v1_rows), f"Expected {len(v1_rows)} rows in equations_v2, got {len(v2_rows)}."
    assert len({row[0] for row in v2_rows}) == len(v2_rows), "Duplicate IDs found in equations_v2."
    v2_dict = {row[0]: (row[1], row[2]) for row in v2_rows}
    wrong_status = []
    for row_id, expression in v1_rows:
        assert row_id in v2_dict, f"Row with id {row_id} missing in equations_v2."
        migrated_expression, status = v2_dict[row_id]
        assert expression == migrated_expression, f"Expression for id {row_id} was altered."
        expected = "VALID" if python_is_valid(expression) else "INVALID"
        if status != expected:
            wrong_status.append(row_id)
    assert not wrong_status, f"Incorrect status for rows: {wrong_status[:5]}"
    return v1_rows


def test_stage3_schema_migration():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    assert_migrated_database()


def migration_candidates():
    candidates = []
    excluded = {os.path.realpath(SANITIZER), os.path.realpath(SANITIZER_SOURCE), os.path.realpath(DB_PATH)}
    for base in ("/home/user", "/app"):
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".git"}]
            for name in files:
                path = os.path.join(root, name)
                if os.path.realpath(path) in excluded or not os.path.isfile(path):
                    continue
                try:
                    if os.path.getsize(path) > 2_000_000:
                        continue
                    data = open(path, "rb").read()
                except OSError:
                    continue
                if b"equations_v1" in data and b"equations_v2" in data:
                    candidates.append(path)
    return sorted(set(candidates), key=lambda p: ("migrat" not in os.path.basename(p).lower(), p))


def commands_for_candidate(path):
    if path.endswith(".py"):
        base = [["python3", path]]
    elif path.endswith((".sh", ".bash")):
        base = [["bash", path]]
    elif path.endswith(".c"):
        output = tempfile.mktemp(prefix="migration_c_", dir="/tmp")
        compiled = subprocess.run(["gcc", path, "-o", output, "-lsqlite3"], capture_output=True, text=True)
        base = [[output]] if compiled.returncode == 0 else []
    elif os.access(path, os.X_OK):
        base = [[path]]
    else:
        try:
            first = open(path, "rb").readline(200)
        except OSError:
            first = b""
        base = [["bash", path]] if first.startswith(b"#!") else []
    return base + [command + [DB_PATH] for command in base]


def test_stage3_pipeline_handles_new_rows_and_invokes_sanitizer():
    candidates = migration_candidates()
    assert candidates, "No migration script/program containing the equations_v1 to equations_v2 pipeline was found."

    clean, evil = generated_corpus()
    new_expressions = clean[-12:] + evil[-18:]

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COALESCE(MAX(id), 0) FROM equations_v1")
        next_id = cursor.fetchone()[0] + 1000
        for offset, expression in enumerate(new_expressions):
            cursor.execute("INSERT INTO equations_v1(id, expression) VALUES (?, ?)", (next_id + offset, expression))
        cursor.execute("DROP TABLE IF EXISTS equations_v2")
        conn.commit()
    finally:
        conn.close()

    pristine = "/tmp/math_data_before_dynamic_migration.db"
    shutil.copy2(DB_PATH, pristine)

    real_sanitizer = f"/tmp/sanitizer.real.{os.getpid()}"
    call_log = f"/tmp/sanitizer.calls.{os.getpid()}"
    os.rename(SANITIZER, real_sanitizer)
    wrapper = f"#!/bin/sh\nprintf '%s\\n' \"$1\" >> {call_log}\nexec {real_sanitizer} \"$@\"\n"
    with open(SANITIZER, "w") as handle:
        handle.write(wrapper)
    os.chmod(SANITIZER, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    success = False
    failures = []
    try:
        for candidate in candidates:
            for command in commands_for_candidate(candidate):
                shutil.copy2(pristine, DB_PATH)
                if os.path.exists(call_log):
                    os.unlink(call_log)
                try:
                    result = subprocess.run(command, cwd=os.path.dirname(candidate), capture_output=True, text=True, timeout=30)
                    if result.returncode != 0:
                        failures.append(f"{command}: exit {result.returncode}")
                        continue
                    all_rows = assert_migrated_database()
                    calls = []
                    if os.path.exists(call_log):
                        with open(call_log) as handle:
                            calls = [line.rstrip("\n") for line in handle]
                    needed = collections.Counter(expression for _, expression in all_rows)
                    seen = collections.Counter(calls)
                    assert all(seen[expr] >= count for expr, count in needed.items()), (
                        "Migration did not pass every equations_v1 expression through /home/user/sanitizer."
                    )
                    success = True
                    break
                except Exception as exc:
                    failures.append(f"{command}: {exc}")
            if success:
                break
    finally:
        if os.path.lexists(SANITIZER):
            os.unlink(SANITIZER)
        os.rename(real_sanitizer, SANITIZER)

    assert success, "No submitted migration pipeline successfully handled added rows. " + " | ".join(failures[:5])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
