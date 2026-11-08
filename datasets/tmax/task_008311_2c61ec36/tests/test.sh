#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import shutil
import subprocess
from fractions import Fraction

import pytest

BASE_DIR = "/home/user/matheval"
BUILD_DIR = os.path.join(BASE_DIR, "build")
LIB_PATH = os.path.join(BUILD_DIR, "libmatheval.so")


def test_cmakelists_fixed():
    """Check if CMakeLists.txt was fixed to link the correct library."""
    cmake_path = os.path.join(BASE_DIR, "CMakeLists.txt")
    assert os.path.isfile(cmake_path), f"{cmake_path} is missing."

    with open(cmake_path, "r") as f:
        content = f.read()

    assert "matheval_lib" not in content, "CMakeLists.txt still contains the incorrect 'matheval_lib' link target."
    assert "target_link_libraries(test_eval matheval)" in content.replace(" ", "") or \
           "target_link_libraries(test_evalmatheval)" in content.replace(" ", ""), \
           "CMakeLists.txt must link test_eval to matheval."


def test_eval_c_fixed():
    """Check if eval.c logic bugs for subtraction and division are fixed."""
    eval_c_path = os.path.join(BASE_DIR, "src", "eval.c")
    assert os.path.isfile(eval_c_path), f"{eval_c_path} is missing."

    with open(eval_c_path, "r") as f:
        content = f.read()

    assert "val1 - val2" not in content, "eval.c still contains the subtraction bug (val1 - val2)."
    assert "val1 / val2" not in content, "eval.c still contains the division bug (val1 / val2)."
    assert "val2 - val1" in content, "eval.c should subtract val1 from val2."
    assert "val2 / val1" in content, "eval.c should divide val2 by val1."


def test_build_and_ctest_pass():
    """Check if the project builds and tests pass."""
    assert os.path.isdir(BUILD_DIR), f"{BUILD_DIR} is missing."

    cmake_proc = subprocess.run(["cmake", ".."], cwd=BUILD_DIR, capture_output=True, text=True, timeout=60)
    assert cmake_proc.returncode == 0, f"CMake configuration failed:\n{cmake_proc.stderr}"

    clean_proc = subprocess.run(["make", "clean"], cwd=BUILD_DIR, capture_output=True, text=True, timeout=60)
    assert clean_proc.returncode == 0, f"Make clean failed:\n{clean_proc.stderr}"

    make_proc = subprocess.run(["make"], cwd=BUILD_DIR, capture_output=True, text=True, timeout=60)
    assert make_proc.returncode == 0, f"Make build failed:\n{make_proc.stderr}"

    list_proc = subprocess.run(["ctest", "-N"], cwd=BUILD_DIR, capture_output=True, text=True, timeout=30)
    assert list_proc.returncode == 0, f"Unable to enumerate CTest tests:\n{list_proc.stdout}\n{list_proc.stderr}"
    total_lines = [line for line in list_proc.stdout.splitlines() if "Total Tests:" in line]
    assert total_lines and int(total_lines[-1].split(":", 1)[1].strip()) > 0, "CTest must contain at least one test."

    ctest_proc = subprocess.run(["ctest", "--output-on-failure"], cwd=BUILD_DIR, capture_output=True, text=True, timeout=60)
    assert ctest_proc.returncode == 0, f"ctest failed. Tests did not pass or executable could not find shared library:\n{ctest_proc.stderr}\n{ctest_proc.stdout}"
    assert "100% tests passed" in ctest_proc.stdout, f"CTest did not report 100% passing tests:\n{ctest_proc.stdout}"
    assert os.path.isfile(LIB_PATH), f"Expected shared library {LIB_PATH} was not built."


def test_compiled_library_general_rpn_behavior():
    """Exercise the freshly built library on runtime-generated RPN expressions."""
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} is missing."
    lib = ctypes.CDLL(LIB_PATH)
    fn = lib.eval_rpn
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_double
    rng = random.SystemRandom()

    cases = []
    for op in ["+", "-", "*", "/"]:
        a = rng.randint(-50, 50)
        b = rng.choice([n for n in range(-20, 21) if n != 0])
        expected = {"+": a + b, "-": a - b, "*": a * b, "/": a / b}[op]
        cases.append((f"{a} {b} {op}", float(expected)))

    def make_tree(depth):
        if depth == 0 or (depth > 1 and rng.randrange(4) == 0):
            value = rng.randint(-9, 9)
            return str(value), Fraction(value)
        left_expr, left_value = make_tree(depth - 1)
        right_expr, right_value = make_tree(depth - 1)
        op = rng.choice(["+", "-", "*", "/"])
        if op == "/" and right_value == 0:
            op = rng.choice(["+", "-", "*"])
        if op == "+":
            value = left_value + right_value
        elif op == "-":
            value = left_value - right_value
        elif op == "*":
            value = left_value * right_value
        else:
            value = left_value / right_value
        return f"{left_expr} {right_expr} {op}", value

    while len(cases) < 35:
        expr, expected = make_tree(rng.randint(2, 4))
        cases.append((expr, float(expected)))

    for expr, expected in cases:
        actual = fn(expr.encode("ascii"))
        assert math.isfinite(actual), f"Non-finite result for {expr!r}: {actual}"
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), \
            f"Incorrect evaluation for {expr!r}: expected {expected}, got {actual}"


def _run_integration(script_path, log_path):
    if os.path.exists(log_path):
        os.remove(log_path)
    proc = subprocess.run(["python3", script_path], cwd=BASE_DIR, capture_output=True, text=True, timeout=30)
    assert proc.returncode == 0, f"Integration script failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.isfile(log_path), f"{log_path} is missing after running the integration script."
    with open(log_path, "r") as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError as exc:
        raise AssertionError(f"Integration log is not a float string: {content!r}") from exc
    return content, value


def test_integration_result_log():
    """Run the Python artifact and verify that its output comes from the loaded C function."""
    script_path = os.path.join(BASE_DIR, "integration_test.py")
    log_path = os.path.join(BASE_DIR, "integration_result.log")
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} is missing."

    content, value = _run_integration(script_path, log_path)
    assert "5.0" in content, f"Expected the result log to contain '5.0', but got: '{content}'"
    assert value == 5.0, f"Expected exactly 5.0 from the required expression, got {value}"

    sentinel = float(random.SystemRandom().randint(100000, 900000)) + 0.25
    probe_source = "/tmp/matheval_probe.c"
    probe_library = "/tmp/libmatheval_probe.so"
    backup_library = "/tmp/libmatheval_original.so"
    with open(probe_source, "w") as f:
        f.write(f"double eval_rpn(const char *expr) {{ (void)expr; return {sentinel:.2f}; }}\n")
    compile_proc = subprocess.run(
        ["gcc", "-shared", "-fPIC", probe_source, "-o", probe_library],
        capture_output=True, text=True, timeout=30
    )
    assert compile_proc.returncode == 0, f"Failed to build verifier probe library:\n{compile_proc.stderr}"

    if os.path.lexists(backup_library):
        os.remove(backup_library)
    os.replace(LIB_PATH, backup_library)
    try:
        shutil.copy2(probe_library, LIB_PATH)
        _, probe_value = _run_integration(script_path, log_path)
        assert probe_value == sentinel, \
            "integration_test.py did not write the value returned by eval_rpn from build/libmatheval.so"
    finally:
        if os.path.lexists(LIB_PATH):
            os.remove(LIB_PATH)
        os.replace(backup_library, LIB_PATH)

    final_content, final_value = _run_integration(script_path, log_path)
    assert "5.0" in final_content, f"Expected the restored integration result to contain '5.0', got {final_content!r}"
    assert final_value == 5.0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
