#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import pytest

WORKSPACE = "/home/user/workspace"
LIB = os.path.join(WORKSPACE, "libcalc.so")
EVALUATOR = os.path.join(WORKSPACE, "evaluator.py")
PROGRAM = os.path.join(WORKSPACE, "program.txt")
RESULTS = os.path.join(WORKSPACE, "results.txt")
GO_DIR = os.path.join(WORKSPACE, "go_calc")
ORIGINAL_EXPECTED = ["15", "16", "42", "11"]


def read_results():
    assert os.path.isfile(RESULTS), "results.txt is missing"
    with open(RESULTS, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def run_evaluator():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        ["python3", EVALUATOR],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"evaluator.py failed:\n{proc.stdout}\n{proc.stderr}"


def test_libcalc_so_exists():
    assert os.path.isfile(LIB), "libcalc.so was not built in /home/user/workspace"


def test_evaluator_py_exists():
    assert os.path.isfile(EVALUATOR), "evaluator.py is missing"


def test_results_txt_correct():
    assert read_results() == ORIGINAL_EXPECTED, (
        f"results.txt content is incorrect. Expected {ORIGINAL_EXPECTED}, got {read_results()}"
    )


def test_no_circular_dependency():
    util_path = os.path.join(GO_DIR, "util", "util.go")
    ops_path = os.path.join(GO_DIR, "ops", "ops.go")

    if os.path.isfile(util_path) and os.path.isfile(ops_path):
        with open(util_path, "r") as f:
            util_content = f.read()
        with open(ops_path, "r") as f:
            ops_content = f.read()

        util_imports_ops = '"go_calc/ops"' in util_content
        ops_imports_util = '"go_calc/util"' in ops_content
        assert not (util_imports_ops and ops_imports_util), "Circular dependency between util and ops still exists"


def test_go_project_builds_as_c_shared_library():
    assert os.path.isdir(GO_DIR), "go_calc project is missing"
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "libcalc.so")
        proc = subprocess.run(
            ["go", "build", "-buildmode=c-shared", "-o", rebuilt, "."],
            cwd=GO_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert proc.returncode == 0, f"Go project does not build as a C-shared library:\n{proc.stderr}"
        rebuilt_lib = ctypes.CDLL(rebuilt)
        rebuilt_compute = rebuilt_lib.Compute
        rebuilt_compute.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
        rebuilt_compute.restype = ctypes.c_int
        assert rebuilt_compute(17, -4, 1) == 13
        assert rebuilt_compute(17, -4, 2) == 21
        assert rebuilt_compute(17, -4, 3) == -68


def test_submitted_library_is_go_shared_object_and_compute_works():
    info = subprocess.run(
        ["go", "version", "-m", LIB],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert info.returncode == 0 and "buildmode=c-shared" in info.stdout, (
        "libcalc.so is not a Go C-shared library"
    )

    try:
        lib = ctypes.CDLL(LIB)
        compute = lib.Compute
    except Exception as exc:
        pytest.fail(f"libcalc.so could not be loaded or does not export Compute: {exc}")
    compute.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
    compute.restype = ctypes.c_int

    rng = random.SystemRandom()
    for _ in range(12):
        a = rng.randint(-10000, 10000)
        b = rng.randint(-10000, 10000)
        assert compute(a, b, 1) == a + b
        assert compute(a, b, 2) == a - b
        assert compute(a, b, 3) == a * b


def test_evaluator_parses_dynamic_program_and_calls_compute_via_ctypes():
    with open(EVALUATOR, "r") as f:
        evaluator_source = f.read()
    try:
        tree = ast.parse(evaluator_source)
    except SyntaxError as exc:
        pytest.fail(f"evaluator.py is not valid Python: {exc}")
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "evaluator.py must use ctypes"

    token = uuid.uuid4().hex
    backup_lib = os.path.join(WORKSPACE, ".libcalc.backup." + token)
    log_path = os.path.join("/tmp", "compute_calls_" + token)
    with open(PROGRAM, "rb") as f:
        original_program = f.read()

    rng = random.SystemRandom()
    operands = [(rng.randint(-50, 50), rng.randint(-50, 50)) for _ in range(3)]
    operations = [("ADD", 1), ("SUB", 2), ("MUL", 3)]

    def shim_value(a, b, op):
        if op == 1:
            return a + b + 100003
        if op == 2:
            return a - b - 200003
        return a * b + 300007

    lines = []
    expected_results = []
    expected_calls = []
    for (a, b), (name, op) in zip(operands, operations):
        lines.extend([f"PUSH {a}", f"PUSH {b}", name, "PRINT"])
        expected_results.append(str(shim_value(a, b, op)))
        expected_calls.append(f"{a} {b} {op}")

    c_source = f'''#include <stdio.h>
int Compute(int a, int b, int op) {{
    FILE *f = fopen("{log_path}", "a");
    if (f) {{ fprintf(f, "%d %d %d\\n", a, b, op); fclose(f); }}
    if (op == 1) return a + b + 100003;
    if (op == 2) return a - b - 200003;
    if (op == 3) return a * b + 300007;
    return -987654321;
}}
'''

    try:
        os.rename(LIB, backup_lib)
        with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as src:
            src.write(c_source)
            src_path = src.name
        try:
            proc = subprocess.run(
                ["gcc", "-shared", "-fPIC", "-o", LIB, src_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert proc.returncode == 0, f"Failed to prepare verifier probe library: {proc.stderr}"
        finally:
            os.remove(src_path)

        with open(PROGRAM, "w") as f:
            f.write("\n".join(lines) + "\n")
        run_evaluator()
        assert read_results() == expected_results, (
            "evaluator.py did not evaluate a dynamically generated program using Compute results"
        )
        assert os.path.isfile(log_path), "evaluator.py did not call the shared library's Compute function"
        with open(log_path, "r") as f:
            calls = [line.strip() for line in f if line.strip()]
        assert calls == expected_calls, (
            f"Compute must be called once for every operation with left/right operands and op codes; got {calls}"
        )
    finally:
        if os.path.exists(LIB):
            os.remove(LIB)
        if os.path.exists(backup_lib):
            os.rename(backup_lib, LIB)
        with open(PROGRAM, "wb") as f:
            f.write(original_program)
        if os.path.exists(log_path):
            os.remove(log_path)
        run_evaluator()

    assert read_results() == ORIGINAL_EXPECTED, "evaluator.py failed when rerun on the supplied program.txt"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
