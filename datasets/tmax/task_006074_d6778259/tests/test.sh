#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import subprocess
import sys

PROJECT_DIR = "/home/user/collatz_ext"
REPORT_PATH = os.path.join(PROJECT_DIR, "fix_report.txt")
LIB_PATH = os.path.join(PROJECT_DIR, "libcollatz.so")
MAKEFILE_PATH = os.path.join(PROJECT_DIR, "Makefile")
SOURCE_PATH = os.path.join(PROJECT_DIR, "collatz.c")


def collatz_reference(n):
    count = 0
    while n > 1:
        if n % 2 == 0:
            n //= 2
        else:
            n = 3 * n + 1
        count += 1
    return count


def assert_valid_shared_object(path):
    assert os.path.isfile(path), f"Shared library {path} was not found."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary."
    result = subprocess.run(
        ["readelf", "-h", path], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, result.stderr
    assert "DYN (Shared object file)" in result.stdout, f"{path} is not a shared object."


def exercise_library(path):
    values = [1, 2, 3, 5, 6, 7, 12, 19, 27, 97, 871, 6171]
    rng = secrets.SystemRandom()
    values.extend(rng.randrange(2, 1_000_000) for _ in range(30))
    cases = [[n, collatz_reference(n)] for n in values]

    checker = r'''import ctypes, json, sys
lib = ctypes.CDLL(sys.argv[1])
func = lib.collatz_length
func.argtypes = [ctypes.c_longlong]
func.restype = ctypes.c_int
for n, expected in json.loads(sys.argv[2]):
    actual = func(n)
    if actual != expected:
        raise AssertionError(f"collatz_length({n}) returned {actual}, expected {expected}")
'''
    result = subprocess.run(
        [sys.executable, "-c", checker, path, json.dumps(cases)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_fix_report_exists():
    """Check that the fix_report.txt file exists."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."


def test_fix_report_content():
    """Check that the fix_report.txt contains the correct output."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Report file {REPORT_PATH} does not contain enough lines. Found {len(lines)}."
    assert lines[0] == "SUCCESS", f"Expected first line to be 'SUCCESS', but got '{lines[0]}'."
    assert lines[1] == "111", f"Expected second line to be '111' (the Collatz sequence length for n=27), but got '{lines[1]}'."

    with open(REPORT_PATH, "r") as f:
        exact_lines = f.read().splitlines()
    assert exact_lines == ["SUCCESS", "111"], "fix_report.txt must contain exactly the required two lines."
    assert int(exact_lines[1]) == collatz_reference(27)


def test_shared_library_exists():
    """Check that the shared library was built."""
    assert os.path.exists(LIB_PATH), f"Shared library {LIB_PATH} was not found. The Makefile might not be properly fixed or executed."


def test_makefile_fixed():
    """Check that the Makefile was modified to include shared library flags."""
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile {MAKEFILE_PATH} does not exist."

    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()

    assert "-shared" in content, "Makefile does not contain the '-shared' flag required for building a shared library."
    assert "-fPIC" in content, "Makefile does not contain the '-fPIC' flag required for Position Independent Code."


def test_make_builds_and_library_works():
    clean = subprocess.run(
        ["make", "clean"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=30
    )
    assert clean.returncode == 0, clean.stdout + clean.stderr
    if os.path.lexists(LIB_PATH):
        os.remove(LIB_PATH)

    build = subprocess.run(
        ["make", "all"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=60
    )
    assert build.returncode == 0, build.stdout + build.stderr
    assert_valid_shared_object(LIB_PATH)
    exercise_library(LIB_PATH)


def test_run_tests_orchestration_succeeds():
    result = subprocess.run(
        [sys.executable, "run_tests.py"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert_valid_shared_object(LIB_PATH)
    exercise_library(LIB_PATH)


def test_collatz_source_itself_is_fixed():
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} does not exist."
    output = "/tmp/libcollatz_source_check.so"
    if os.path.exists(output):
        os.remove(output)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-Wall", "-Wextra", "-o", output, SOURCE_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert_valid_shared_object(output)
    exercise_library(output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
