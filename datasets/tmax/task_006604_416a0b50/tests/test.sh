#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/run_service_and_check.py
import asyncio
import json
import sys

sys.path.insert(0, "/home/user")
import service

if len(sys.argv) != 3:
    raise SystemExit("usage: run_service_and_check.py DB OUTPUT")

db_path, output_path = sys.argv[1:]
sys.argv = ["service.py", "--db", db_path, "--output", output_path]
asyncio.run(service.main())

active = getattr(service, "active_tasks", set())
if active:
    raise AssertionError(f"service retained {len(active)} completed task reference(s)")

with open(output_path) as f:
    data = json.load(f)
if not isinstance(data, list):
    raise AssertionError("service output is not a list")
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
import random
import sqlite3
import statistics
import subprocess
import sys

import pytest

HOME = "/home/user"
EXPECTED_ROWS = [
    (1, 100000000.0, 100000000.00001, 100000000.00002),
    (2, 100000000.00003, 100000000.00004, 100000000.00005),
    (3, 100000000.00006, 100000000.00007, 100000000.00008),
]


def load_math_utils():
    path = "/home/user/math_utils.py"
    assert os.path.isfile(path), f"math_utils.py missing at {path}"
    spec = importlib.util.spec_from_file_location("submitted_math_utils", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def configured_shell(command):
    # Exercise common persistent environment fixes while retaining system loader
    # configuration (for example, ldconfig or /etc/ld.so.conf.d entries).
    script = r'''
export HOME=/home/user
set -a
[ -f /etc/environment ] && . /etc/environment
for f in /etc/profile.d/*.sh; do [ -f "$f" ] && . "$f"; done
[ -f /home/user/.profile ] && . /home/user/.profile
[ -f /home/user/.bashrc ] && . /home/user/.bashrc
set +a
''' + command
    env = os.environ.copy()
    env["HOME"] = HOME
    return subprocess.run(
        ["bash", "-ic", script], capture_output=True, text=True, env=env
    )


def test_recovered_database():
    db_path = "/home/user/recovered_data.db"
    assert os.path.isfile(db_path), f"Recovered database missing at {db_path}"

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM sensors")
        count = cursor.fetchone()[0]
        cursor.execute("SELECT id, val1, val2, val3 FROM sensors ORDER BY id")
        rows = cursor.fetchall()
        cursor.execute("PRAGMA integrity_check")
        integrity = cursor.fetchone()[0]
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Could not read from recovered database: {e}")

    assert count == 3, f"Expected 3 rows in recovered database, found {count}"
    assert rows == EXPECTED_ROWS, f"Recovered sensor data is incorrect: {rows!r}"
    assert integrity == "ok", f"Recovered database failed integrity_check: {integrity}"


def test_calc_variance_is_numerically_stable():
    calc_variance = load_math_utils().calc_variance
    probe = calc_variance([1.0, 2.0, 3.0])
    if math.isclose(probe, statistics.pvariance([1.0, 2.0, 3.0]), rel_tol=1e-12, abs_tol=1e-15):
        reference = statistics.pvariance
    elif math.isclose(probe, statistics.variance([1.0, 2.0, 3.0]), rel_tol=1e-12, abs_tol=1e-15):
        reference = statistics.variance
    else:
        pytest.fail(f"calc_variance returned an invalid variance for [1,2,3]: {probe!r}")

    requested = [100000000.0, 100000000.00001, 100000000.00002]
    cases = [
        requested,
        [1.25, -2.5, 7.75, 3.0],
        [100000000.0, 100000000.0002, 99999999.9997, 100000000.0005],
    ]
    rng = random.Random(812734)
    for _ in range(10):
        baseline = 100000000.0 + rng.randint(-100, 100) * 1000.0
        cases.append([baseline + rng.randint(-100, 100) * 0.0001 for _ in range(7)])

    for values in cases:
        actual = calc_variance(values)
        expected = reference(values)
        assert isinstance(actual, (int, float)) and math.isfinite(actual)
        assert actual >= 0
        tolerance = 1e-10 if max(values) - min(values) > 1 else 0.02
        assert math.isclose(actual, expected, rel_tol=tolerance, abs_tol=1e-24), (
            f"unstable/incorrect variance for {values!r}: got {actual!r}, expected {expected!r}"
        )
    assert calc_variance(requested) != 0.0


def test_shared_library_environment_and_real_service_execution(tmp_path):
    loader = configured_shell(
        "python3 -c 'import ctypes; ctypes.CDLL(\"libfastmath.so\")'"
    )
    assert loader.returncode == 0, (
        "Configured environment cannot resolve libfastmath.so by name:\n"
        + loader.stdout + loader.stderr
    )

    fresh_output = tmp_path / "fresh_output.json"
    command = (
        "python3 /tmp/run_service_and_check.py "
        f"/home/user/recovered_data.db {fresh_output}"
    )
    result = configured_shell(command)
    assert result.returncode == 0, (
        "The fixed service failed when actually executed:\n" + result.stdout + result.stderr
    )

    with fresh_output.open() as f:
        fresh = json.load(f)
    calc_variance = load_math_utils().calc_variance
    expected = [
        {"id": row[0], "variance": calc_variance(list(row[1:]))}
        for row in EXPECTED_ROWS
    ]
    assert fresh == expected, f"Service produced incorrect records: {fresh!r}"

    with open("/home/user/processed_output.json") as f:
        submitted = json.load(f)
    assert submitted == fresh, "processed_output.json is not the output of the fixed service"


def test_processed_output():
    out_path = "/home/user/processed_output.json"
    assert os.path.isfile(out_path), f"Processed output missing at {out_path}"

    with open(out_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Processed output is not valid JSON")

    assert isinstance(data, list), "Processed output should be a JSON list"
    assert len(data) == 3, f"Expected 3 records in processed output, found {len(data)}"

    for record in data:
        assert "id" in record, "Record missing 'id'"
        assert "variance" in record, "Record missing 'variance'"
        assert isinstance(record["variance"], float) or isinstance(record["variance"], int), "Variance should be a number"
        assert record["variance"] > 0, "Variance should be strictly positive (not zero or negative due to catastrophic cancellation)"


def test_service_memory_leak_fixed(tmp_path):
    service_path = "/home/user/service.py"
    assert os.path.isfile(service_path), f"Service file missing at {service_path}"

    with open(service_path, "r") as f:
        content = f.read()

    has_discard = "active_tasks.discard" in content
    has_remove = "active_tasks.remove" in content
    has_add = "active_tasks.add" in content

    fixed = has_discard or has_remove or not has_add
    assert fixed, "Memory leak in service.py is not fixed (tasks are added to active_tasks but never removed)"

    db = tmp_path / "many.db"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE sensors (id INTEGER PRIMARY KEY, val1 REAL, val2 REAL, val3 REAL)")
    conn.executemany(
        "INSERT INTO sensors VALUES (?, ?, ?, ?)",
        [(i, 100000000.0 + i, 100000000.00001 + i, 100000000.00002 + i) for i in range(1, 41)],
    )
    conn.commit()
    conn.close()
    output = tmp_path / "many.json"
    result = configured_shell(f"python3 /tmp/run_service_and_check.py {db} {output}")
    assert result.returncode == 0, (
        "Service retained task references or failed under repeated processing:\n"
        + result.stdout + result.stderr
    )
    with output.open() as f:
        assert len(json.load(f)) == 40


def test_regression_test():
    test_path = "/home/user/test_regression.py"
    assert os.path.isfile(test_path), f"Regression test file missing at {test_path}"

    # Run the user's unittest suite
    result = subprocess.run(
        ["python", "-m", "unittest", test_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Regression tests failed:\n{result.stdout}\n{result.stderr}"

    with open(test_path) as f:
        tree = ast.parse(f.read(), filename=test_path)
    imports_calc = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "math_utils"
        and any(alias.name == "calc_variance" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_calc, "Regression test must import calc_variance from math_utils"

    check_suite = subprocess.run(
        [sys.executable, "-c", (
            "import importlib.util,unittest;"
            "p='/home/user/test_regression.py';"
            "s=importlib.util.spec_from_file_location('user_regression',p);"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            "q=unittest.defaultTestLoader.loadTestsFromModule(m);"
            "assert q.countTestCases() >= 1, 'no unittest test cases found';"
            "r=unittest.TestResult();q.run(r);"
            "assert r.testsRun >= 1 and not r.errors and not r.failures and not r.skipped"
        )], capture_output=True, text=True, cwd="/home/user"
    )
    assert check_suite.returncode == 0, (
        "Regression suite must contain and run at least one non-skipped unittest:\n"
        + check_suite.stdout + check_suite.stderr
    )


def test_fix_summary():
    log_path = "/home/user/fix_summary.log"
    assert os.path.isfile(log_path), f"Summary log missing at {log_path}"

    with open(log_path, "r") as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]

    assert len(lines) >= 3, f"Expected at least 3 lines in summary log, found {len(lines)}"
    assert len(raw_lines) == 3 and all(line.strip() for line in raw_lines), "Summary log must contain exactly three non-empty lines"
    assert lines[0] == "3", f"Line 1 (rows recovered) should be '3', got '{lines[0]}'"

    try:
        variance = float(lines[1])
    except ValueError:
        pytest.fail(f"Line 2 (variance) could not be parsed as float: '{lines[1]}'")

    expected_var = statistics.variance([100000000.0, 100000000.00001, 100000000.00002])
    assert 0 < variance < 1e-9, f"Line 2 (variance) is not in the expected range. Got {variance}, expected close to {expected_var}"
    actual_var = load_math_utils().calc_variance([100000000.0, 100000000.00001, 100000000.00002])
    assert variance == actual_var, f"Line 2 must be the exact calc_variance result {actual_var!r}, got {lines[1]!r}"

    assert lines[2] == "3", f"Line 3 (last record id) should be '3', got '{lines[2]}'"
    with open("/home/user/processed_output.json") as f:
        output = json.load(f)
    assert output and str(output[-1]["id"]) == lines[2]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
