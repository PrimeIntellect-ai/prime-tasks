#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import string
import subprocess

import pytest

PROJECT = "/home/user/polybuild"
LIB_PATH = os.path.join(PROJECT, "libpolyhash.so")
RUNNER_PATH = os.path.join(PROJECT, "test_runner")
RESULT_PATH = os.path.join(PROJECT, "result.txt")
LOG_PATH = os.path.join(PROJECT, "valgrind.log")


def expected_hash(text, x):
    result = 0
    x_pow = 1
    for byte in text.encode("ascii"):
        result += byte * x_pow
        x_pow *= x
    return result


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_exercise_project():
    # Preserve the required agent-generated report check before exercising the build.
    assert os.path.isfile(LOG_PATH), f"File {LOG_PATH} is missing."
    with open(LOG_PATH, "r", errors="replace") as f:
        submitted_log = f.read()
    assert (
        "definitely lost: 0 bytes in 0 blocks" in submitted_log
        or "All heap blocks were freed -- no leaks are possible" in submitted_log
    ), "Valgrind log does not indicate that memory leaks were resolved (expected 0 bytes definitely lost)."

    # Force the submitted Makefile to rebuild both required artifacts from the project sources.
    for path in (LIB_PATH, RUNNER_PATH, os.path.join(PROJECT, "src", "polyhash.o")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    build = subprocess.run(
        ["make"], cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"

    assert os.path.isfile(LIB_PATH), f"File {LIB_PATH} is missing after make."
    assert os.path.isfile(RUNNER_PATH), f"File {RUNNER_PATH} is missing after make."
    assert os.access(RUNNER_PATH, os.X_OK), f"File {RUNNER_PATH} is not executable."

    # Ensure test_runner is genuinely linked against and uses the library interface.
    symbols = subprocess.run(
        ["nm", "-D", RUNNER_PATH], text=True, capture_output=True, timeout=10
    )
    assert symbols.returncode == 0, f"Could not inspect test_runner: {symbols.stderr}"
    assert any(
        line.split()[-1] == "poly_hash" and " U " in f" {line} "
        for line in symbols.stdout.splitlines()
        if line.split()
    ), "test_runner is not linked to the poly_hash interface."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT + os.pathsep + env.get("LD_LIBRARY_PATH", "")

    # Remove any precomputed answer and require the rebuilt runner to generate it.
    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass
    run = subprocess.run(
        [RUNNER_PATH], cwd=PROJECT, env=env, text=True,
        capture_output=True, timeout=15
    )
    assert run.returncode == 0, f"test_runner failed:\n{run.stdout}\n{run.stderr}"
    assert os.path.isfile(RESULT_PATH), "test_runner did not generate result.txt."

    # Independently run the rebuilt executable under Valgrind and require a clean result.
    vg = subprocess.run(
        [
            "valgrind", "--leak-check=full", "--show-leak-kinds=all",
            "--errors-for-leak-kinds=definite", "--error-exitcode=97",
            RUNNER_PATH,
        ],
        cwd=PROJECT, env=env, text=True, capture_output=True, timeout=30
    )
    assert vg.returncode == 0, f"Valgrind detected an error or leak:\n{vg.stderr}"
    assert (
        "definitely lost: 0 bytes in 0 blocks" in vg.stderr
        or "All heap blocks were freed -- no leaks are possible" in vg.stderr
    ), f"Runtime Valgrind output does not show a leak-free execution:\n{vg.stderr}"


def test_result_txt():
    """Test that result.txt exists and contains the correct hash output."""
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} is missing."
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    assert content == "64923478", f"Expected '64923478' in result.txt, but got '{content}'."


def test_valgrind_log():
    """Test that valgrind.log exists and shows no definite memory leaks."""
    assert os.path.isfile(LOG_PATH), f"File {LOG_PATH} is missing."
    with open(LOG_PATH, "r", errors="replace") as f:
        content = f.read()
    no_leaks = (
        "definitely lost: 0 bytes in 0 blocks" in content
        or "All heap blocks were freed -- no leaks are possible" in content
    )
    assert no_leaks, "Valgrind log does not indicate that memory leaks were resolved (expected 0 bytes definitely lost)."


def test_shared_library():
    """Test that libpolyhash.so is correctly built as a shared object library."""
    assert os.path.isfile(LIB_PATH), f"File {LIB_PATH} is missing."
    result = subprocess.run(["file", LIB_PATH], capture_output=True, text=True)
    assert "shared object" in result.stdout, f"{LIB_PATH} is not a valid shared object library. 'file' output: {result.stdout}"


def test_test_runner_executable():
    """Test that test_runner is built and executable."""
    assert os.path.isfile(RUNNER_PATH), f"File {RUNNER_PATH} is missing."
    assert os.access(RUNNER_PATH, os.X_OK), f"File {RUNNER_PATH} is not executable."


def test_poly_hash_behavior_on_derived_inputs():
    """Load the submitted library and validate poly_hash on non-hardcoded inputs."""
    lib = ctypes.CDLL(LIB_PATH)
    poly_hash = lib.poly_hash
    poly_hash.argtypes = [ctypes.c_char_p, ctypes.c_int]
    poly_hash.restype = ctypes.c_longlong

    rng = random.SystemRandom()
    cases = [("A", 3), ("PolyHash", 1), ("abc_123", -2)]
    alphabet = string.ascii_letters + string.digits + "_-"
    for _ in range(12):
        text = "".join(rng.choice(alphabet) for _ in range(rng.randint(2, 10)))
        x = rng.choice([-3, -2, -1, 0, 1, 2, 3, 4, 5])
        cases.append((text, x))

    for text, x in cases:
        actual = poly_hash(text.encode("ascii"), x)
        expected = expected_hash(text, x)
        assert actual == expected, f"poly_hash({text!r}, {x}) returned {actual}, expected {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
