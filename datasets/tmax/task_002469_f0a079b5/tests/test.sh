#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import os
import random
import re
import subprocess
import sys

PROJECT_DIR = "/home/user/project"


def test_directory_structure_and_files():
    expected_files = [
        f"{PROJECT_DIR}/src/c_lib/math_ops.c",
        f"{PROJECT_DIR}/src/c_lib/libmath.so",
        f"{PROJECT_DIR}/src/pylib/interpreter.py",
        f"{PROJECT_DIR}/tests/test_interpreter.py",
        f"{PROJECT_DIR}/tests/test_config.py",
        f"{PROJECT_DIR}/tests/test_integration.py",
        f"{PROJECT_DIR}/test_results.log",
    ]

    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Expected file {file_path} is missing."


def test_no_leftovers_in_root():
    allowed_entries = {"src", "tests", "test_results.log"}
    actual_entries = set(os.listdir(PROJECT_DIR))

    # We allow some flexibility for pytest cache or pycache
    leftovers = [
        entry
        for entry in actual_entries
        if entry not in allowed_entries and not entry.startswith(".")
    ]
    assert not leftovers, f"Found leftover files/directories in root: {leftovers}"


def test_ffi_dynamic_load_logic():
    interpreter_path = f"{PROJECT_DIR}/src/pylib/interpreter.py"
    with open(interpreter_path, "r") as f:
        content = f.read()

    # The requirement says it should resolve the path to ../c_lib/libmath.so relative to itself
    assert "os.path" in content or "Path" in content, (
        "interpreter.py does not seem to dynamically resolve the path using os.path or pathlib."
    )
    assert "c_lib" in content and "libmath.so" in content, (
        "interpreter.py does not reference the relative path to libmath.so properly."
    )


def test_circular_dependency_fixed():
    # We should be able to import interpreter.py without circular import errors
    interpreter_path = f"{PROJECT_DIR}/src/pylib/interpreter.py"

    spec = importlib.util.spec_from_file_location("interpreter", interpreter_path)
    interpreter = importlib.util.module_from_spec(spec)

    # Temporarily add paths so imports work if they rely on sys.path
    sys.path.insert(0, f"{PROJECT_DIR}/src/pylib")
    sys.path.insert(0, f"{PROJECT_DIR}/tests")

    try:
        spec.loader.exec_module(interpreter)
    except Exception as e:
        assert False, (
            "Importing interpreter.py failed, circular dependency might not be fixed. "
            f"Error: {e}"
        )
    finally:
        sys.path.pop(0)
        sys.path.pop(0)


def test_integration_test_contents():
    integration_test_path = f"{PROJECT_DIR}/tests/test_integration.py"
    with open(integration_test_path, "r") as f:
        content = f.read()

    assert "SUB 10 4" in content, "test_integration.py does not test 'SUB 10 4'."
    assert "6" in content, "test_integration.py does not assert the result is 6."


def test_test_results_log():
    log_path = f"{PROJECT_DIR}/test_results.log"
    with open(log_path, "r") as f:
        content = f.read()

    assert "passed" in content.lower(), "test_results.log does not indicate that tests passed."
    assert re.search(r"\b\d+\s+passed\b", content.lower()), (
        "test_results.log does not contain a normal successful pytest summary."
    )


def test_compiled_library_is_loadable_and_correct():
    library_path = f"{PROJECT_DIR}/src/c_lib/libmath.so"
    with open(library_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmath.so is not an ELF shared library."

    library = ctypes.CDLL(library_path)
    library.add.argtypes = [ctypes.c_int, ctypes.c_int]
    library.add.restype = ctypes.c_int
    library.sub.argtypes = [ctypes.c_int, ctypes.c_int]
    library.sub.restype = ctypes.c_int

    rng = random.SystemRandom()
    for _ in range(12):
        left = rng.randint(-10000, 10000)
        right = rng.randint(-10000, 10000)
        assert library.add(left, right) == left + right
        assert library.sub(left, right) == left - right


def test_interpreter_executes_commands_from_an_unrelated_working_directory():
    interpreter_path = f"{PROJECT_DIR}/src/pylib/interpreter.py"
    spec = importlib.util.spec_from_file_location("verified_interpreter", interpreter_path)
    interpreter = importlib.util.module_from_spec(spec)

    old_cwd = os.getcwd()
    sys.path.insert(0, f"{PROJECT_DIR}/src/pylib")
    sys.path.insert(0, f"{PROJECT_DIR}/tests")
    try:
        os.chdir("/tmp")
        spec.loader.exec_module(interpreter)

        assert callable(getattr(interpreter, "evaluate", None)), (
            "interpreter.py does not define a callable evaluate function."
        )

        rng = random.SystemRandom()
        for _ in range(12):
            left = rng.randint(-10000, 10000)
            right = rng.randint(-10000, 10000)
            assert interpreter.evaluate(f"ADD {left} {right}") == left + right
            assert interpreter.evaluate(f"SUB {left} {right}") == left - right
    finally:
        os.chdir(old_cwd)
        sys.path.pop(0)
        sys.path.pop(0)


def test_full_project_pytest_suite_passes():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", f"{PROJECT_DIR}/tests", "-v"],
        cwd="/tmp",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Project pytest suite failed:\n{result.stdout}"
    assert "test_integration.py" in result.stdout, (
        f"pytest did not collect and run the integration test:\n{result.stdout}"
    )
    assert re.search(r"\b\d+\s+passed\b", result.stdout.lower()), (
        f"pytest output did not report passing tests:\n{result.stdout}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
