#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import math
import os
import re
import sqlite3
import subprocess

SIM_DIR = "/home/user/profiling_sim"


def test_libmatrix_compiled():
    """Rebuild the library and verify that the resulting shared object is loadable and functional."""
    build_path = os.path.join(SIM_DIR, "build.sh")
    lib_path = os.path.join(SIM_DIR, "libmatrix.so")
    assert os.path.isfile(build_path), "build.sh is missing."
    assert os.access(build_path, os.X_OK), "build.sh is not executable."

    if os.path.lexists(lib_path):
        os.remove(lib_path)

    result = subprocess.run(
        ["./build.sh"], cwd=SIM_DIR, text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(lib_path), (
        "libmatrix.so was not compiled. Make sure build.sh is fixed and executed."
    )
    assert os.path.isfile(lib_path), "libmatrix.so is not a regular file."

    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmatrix.so is not an ELF shared library."

    lib = ctypes.CDLL(lib_path)
    lib.compute_norm.argtypes = [ctypes.c_double, ctypes.c_double]
    lib.compute_norm.restype = ctypes.c_double
    assert math.isclose(lib.compute_norm(3.0, 4.0), 25.0, rel_tol=0, abs_tol=1e-12)


def test_simulate_py_fixed():
    """Verify both requested source fixes and exercise the square-root implementation."""
    sim_path = os.path.join(SIM_DIR, "simulate.py")
    assert os.path.exists(sim_path), "simulate.py is missing."

    with open(sim_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "if guess == next_guess:" not in content, (
        "The infinite recursion bug in calculate_sqrt was not fixed. "
        "The exact equality check 'guess == next_guess' is still present."
    )
    assert "SUM(duration)" not in content, (
        "The SQL query bug was not fixed. "
        "The script is still querying SUM(duration) instead of the average."
    )

    tree = ast.parse(content, filename=sim_path)
    sqrt_functions = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "calculate_sqrt"
    ]
    assert len(sqrt_functions) == 1, "calculate_sqrt is missing or ambiguously defined."
    sqrt_fn = sqrt_functions[0]

    tolerance_check = False
    for node in ast.walk(sqrt_fn):
        if not isinstance(node, ast.Compare) or len(node.ops) != 1:
            continue
        if not isinstance(node.ops[0], ast.Lt) or len(node.comparators) != 1:
            continue
        rhs = node.comparators[0]
        if not isinstance(rhs, ast.Constant) or not isinstance(rhs.value, (int, float)):
            continue
        if float(rhs.value) != 1e-7:
            continue
        lhs = node.left
        if not isinstance(lhs, ast.Call) or len(lhs.args) != 1:
            continue
        call_name = None
        if isinstance(lhs.func, ast.Name):
            call_name = lhs.func.id
        elif isinstance(lhs.func, ast.Attribute):
            call_name = lhs.func.attr
        if call_name not in ("abs", "fabs"):
            continue
        difference = lhs.args[0]
        if not isinstance(difference, ast.BinOp) or not isinstance(difference.op, ast.Sub):
            continue
        names = {n.id for n in ast.walk(difference) if isinstance(n, ast.Name)}
        if {"guess", "next_guess"}.issubset(names):
            tolerance_check = True
            break

    assert tolerance_check, (
        "calculate_sqrt must terminate using the strict condition "
        "abs(guess - next_guess) < 1e-7."
    )

    sql_strings = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    avg_query = re.compile(
        r"^\s*SELECT\s+AVG\s*\(\s*duration\s*\)\s+FROM\s+runs\s*;?\s*$",
        re.IGNORECASE,
    )
    assert any(avg_query.match(value) for value in sql_strings), (
        "simulate.py must query AVG(duration) from the runs table."
    )

    probe = subprocess.run(
        [
            "python3",
            "-c",
            "import simulate; "
            "n = 1.0 + 2.0 * 5e-8; "
            "r = simulate.calculate_sqrt(n, 1.0); "
            "assert r == 1.0, (r, n)",
        ],
        cwd=SIM_DIR,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert probe.returncode == 0, (
        "calculate_sqrt did not apply the requested tolerance correctly.\n"
        f"stdout:\n{probe.stdout}\nstderr:\n{probe.stderr}"
    )


def test_final_report_content():
    """Run the simulation and compare its real output with the database and report."""
    result = subprocess.run(
        ["python3", "simulate.py"],
        cwd=SIM_DIR,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"simulate.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    output_lines = result.stdout.splitlines()
    assert len(output_lines) == 1, f"simulate.py must print exactly one output line: {result.stdout!r}"
    output = output_lines[0]
    match = re.fullmatch(
        r"Average execution time: ([+-]?(?:\d+(?:\.\d*)?|\.\d+)) ms", output
    )
    assert match, f"Unexpected simulate.py output: {output!r}"

    db_path = os.path.join(SIM_DIR, "metrics.db")
    assert os.path.isfile(db_path), "simulate.py did not create metrics.db."
    with sqlite3.connect(db_path) as conn:
        count, actual_avg, actual_sum = conn.execute(
            "SELECT COUNT(*), AVG(duration), SUM(duration) FROM runs"
        ).fetchone()
    assert count == 5, f"Expected 5 recorded runs, found {count}."
    printed_value = float(match.group(1))
    assert math.isclose(printed_value, actual_avg, rel_tol=0, abs_tol=1e-12), (
        f"Printed value {printed_value} is not the database average {actual_avg}."
    )
    assert not math.isclose(printed_value, actual_sum, rel_tol=0, abs_tol=1e-12), (
        "The printed value is the sum rather than the average."
    )

    report_path = os.path.join(SIM_DIR, "final_report.txt")
    assert os.path.exists(report_path), "final_report.txt was not created."
    with open(report_path, "r") as f:
        report_content = f.read()

    # Preserve the original expected-output assertion.
    expected_output = "Average execution time: 17.5 ms"
    assert expected_output in report_content.strip(), (
        "final_report.txt does not contain the correct output.\n"
        f"Expected to find: '{expected_output}'\n"
        f"Actual content: '{report_content.strip()}'"
    )

    assert report_content in (output, output + "\n"), (
        "final_report.txt must contain exactly the output produced by simulate.py, "
        "with at most its trailing newline."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
