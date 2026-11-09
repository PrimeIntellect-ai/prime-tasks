#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import stat
import subprocess
from fractions import Fraction

PROJECT = "/home/user/stats_engine"


def run(cmd, cwd=PROJECT, timeout=30):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def assert_regular_file(path):
    info = os.lstat(path)
    assert stat.S_ISREG(info.st_mode), f"{path} must be a regular file"


def test_status_file():
    status_path = os.path.join(PROJECT, "status.txt")
    assert os.path.isfile(status_path), "status.txt is missing"
    assert_regular_file(status_path)
    with open(status_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected 'SUCCESS' in status.txt, got '{content}'"


def test_make_test_succeeds_from_clean_build():
    clean = run(["make", "clean"])
    assert clean.returncode == 0, f"'make clean' failed:\n{clean.stdout}\n{clean.stderr}"

    result = run(["make", "test"])
    assert result.returncode == 0, f"'make test' failed with output:\n{result.stdout}\n{result.stderr}"


def test_calculate_variance_on_derived_inputs():
    stats_path = os.path.join(PROJECT, "src", "stats.c")
    assert os.path.isfile(stats_path), "src/stats.c is missing"
    assert_regular_file(stats_path)

    library = "/tmp/libsubmitted_stats.so"
    compile_result = run([
        "gcc", "-std=c11", "-Wall", "-Wextra", "-fPIC", "-shared",
        "-I./src", "-o", library, "src/stats.c", "-lm"
    ])
    assert compile_result.returncode == 0, (
        f"Could not compile submitted stats.c:\n{compile_result.stdout}\n{compile_result.stderr}"
    )

    lib = ctypes.CDLL(library)
    fn = lib.calculate_variance
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    fn.restype = ctypes.c_double

    cases = [
        [1000000000.0, 1000000001.0, 1000000002.0],
        [1000000000.0, 1000000002.0, 1000000004.0],
        [-8.0, -1.0, 3.0, 11.0],
        [42.0],
    ]

    rng = random.SystemRandom()
    for _ in range(40):
        n = rng.randint(2, 18)
        base = rng.randint(100000000, 10000000000)
        spread = rng.choice([3, 10, 100, 1000])
        offsets = [rng.randint(-spread, spread) for _ in range(n)]
        if len(set(offsets)) == 1:
            offsets[-1] += 1
        cases.append([float(base + offset) for offset in offsets])

    for values in cases:
        array_type = ctypes.c_double * len(values)
        actual = fn(array_type(*values), len(values))

        if len(values) <= 1:
            expected = 0.0
        else:
            exact_values = [Fraction.from_float(v) for v in values]
            mean = sum(exact_values, Fraction(0)) / len(exact_values)
            expected_fraction = sum((v - mean) ** 2 for v in exact_values) / (len(values) - 1)
            expected = float(expected_fraction)

        tolerance = 1e-5 * max(1.0, abs(expected))
        assert math.isfinite(actual), f"Non-finite variance for {values}: {actual}"
        assert abs(actual - expected) <= tolerance, (
            f"Incorrect sample variance for {values}: expected {expected}, got {actual}"
        )


def test_minimized_test_exists_and_compiles():
    minimized_test_path = os.path.join(PROJECT, "minimized_test.c")
    assert os.path.isfile(minimized_test_path), "minimized_test.c is missing"
    assert_regular_file(minimized_test_path)

    compile_result = run([
        "gcc", "-I./src", "-o", "minimized_test",
        "minimized_test.c", "src/stats.c", "-lm"
    ])
    assert compile_result.returncode == 0, (
        f"Compilation of minimized_test.c failed:\n{compile_result.stderr}"
    )


def test_minimized_test_execution():
    executable_path = os.path.join(PROJECT, "minimized_test")
    assert os.path.isfile(executable_path), "minimized_test executable is missing, compile step might have failed"

    run_result = run([executable_path])
    assert run_result.returncode == 0, (
        f"minimized_test execution failed (returned {run_result.returncode}). "
        f"Output:\n{run_result.stdout}\n{run_result.stderr}"
    )


def test_minimized_test_really_calls_with_required_values_and_checks_exact_result():
    stub_path = "/tmp/minimized_stats_stub.c"
    with open(stub_path, "w") as f:
        f.write(r'''#include <stdlib.h>
#include <math.h>
#include "stats.h"

static int calls = 0;
static int valid = 1;

static void verify_call(void) __attribute__((destructor));
static void verify_call(void) {
    if (calls != 1 || !valid) _Exit(91);
}

double calculate_variance(double *data, int n) {
    calls++;
    if (n != 3 || data == NULL ||
        data[0] != 1000000000.0 ||
        data[1] != 1000000001.0 ||
        data[2] != 1000000002.0) {
        valid = 0;
        return NAN;
    }
#ifdef RETURN_WRONG_VALUE
    return nextafter(1.0, 2.0);
#else
    return 1.0;
#endif
}
''')

    exact_binary = "/tmp/minimized_exact"
    exact_compile = run([
        "gcc", "-std=c11", "-I./src", "-o", exact_binary,
        "minimized_test.c", stub_path, "-lm"
    ])
    assert exact_compile.returncode == 0, (
        f"Could not instrument minimized_test.c:\n{exact_compile.stdout}\n{exact_compile.stderr}"
    )
    exact_run = run([exact_binary])
    assert exact_run.returncode == 0, (
        "minimized_test.c must call calculate_variance exactly once with the three required values "
        "and return 0 when it returns exactly 1.0"
    )

    wrong_binary = "/tmp/minimized_wrong"
    wrong_compile = run([
        "gcc", "-std=c11", "-DRETURN_WRONG_VALUE", "-I./src", "-o", wrong_binary,
        "minimized_test.c", stub_path, "-lm"
    ])
    assert wrong_compile.returncode == 0, (
        f"Could not instrument minimized_test.c:\n{wrong_compile.stdout}\n{wrong_compile.stderr}"
    )
    wrong_run = run([wrong_binary])
    assert wrong_run.returncode == 1, (
        "minimized_test.c must return 1 when calculate_variance is not strictly equal to 1.0"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
