#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/math_project"
APP = os.path.join(PROJECT, "math_app")


@pytest.fixture(scope="session", autouse=True)
def rebuild_project():
    if os.path.exists(APP):
        os.remove(APP)
    proc = subprocess.run(
        ["make"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f"make failed:\n{proc.stdout}"


def test_makefile_fixed():
    makefile_path = "/home/user/math_project/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not contain the '-lm' linker flag required to fix the build."


def test_math_app_compiled():
    app_path = "/home/user/math_project/math_app"
    assert os.path.isfile(app_path), f"Executable is missing at {app_path}. Did the build succeed?"
    assert os.access(app_path, os.X_OK), f"File at {app_path} is not executable."
    with open(app_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "math_app is not a compiled ELF executable."


def test_results_txt():
    results_path = "/home/user/math_project/results.txt"
    assert os.path.isfile(results_path), f"Results file is missing at {results_path}. Did you run the application?"

    expected_results = [
        60,
        2000000,
        26929944384,
        12000000000
    ]

    with open(results_path, "r") as f:
        lines = f.read().strip().splitlines()

    actual_results = []
    for line in lines:
        try:
            actual_results.append(int(line.strip()))
        except ValueError:
            pytest.fail(f"Found non-integer value in results.txt: '{line}'")

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} results, but found {len(actual_results)}."

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert actual == expected, f"Result at line {i+1} is incorrect. Expected {expected}, got {actual}. The overflow bug might not be properly fixed."


def overflow_cases():
    rng = random.SystemRandom()
    cases = [
        (3000000000, 4000000000),
        (3037000000, 3037000000),
        (15, 20),
        (123456, 654321),
    ]
    while len(cases) < 16:
        common = rng.randrange(1_000_000_000, 2_000_000_000)
        x = rng.randrange(1_000, 40_000)
        y = rng.randrange(1_000, 40_000)
        if math.gcd(x, y) != 1:
            continue
        a, b = common * x, common * y
        expected = abs((a // math.gcd(a, b)) * b)
        if expected <= 2**63 - 1 and a * b > 2**63 - 1:
            cases.append((a, b))
    return cases


def test_c_lcm_implementation_on_overflow_inputs():
    library = "/tmp/libmath_ops_verify.so"
    proc = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-I./include", "src/math_ops.c", "-lm", "-o", library],
        cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f"The C implementation could not be compiled independently:\n{proc.stdout}"

    lib = ctypes.CDLL(library)
    lib.compute_lcm.argtypes = [ctypes.c_longlong, ctypes.c_longlong]
    lib.compute_lcm.restype = ctypes.c_longlong
    for a, b in overflow_cases():
        expected = abs((a // math.gcd(a, b)) * b)
        actual = lib.compute_lcm(a, b)
        assert actual == expected, f"compute_lcm({a}, {b}) returned {actual}, expected {expected}"


def test_built_application_on_derived_inputs():
    cases = overflow_cases()
    expected = [abs((a // math.gcd(a, b)) * b) for a, b in cases]

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "queries.txt")
        output_path = os.path.join(tmpdir, "results.txt")
        with open(input_path, "w") as f:
            for a, b in cases:
                f.write(f"LCM {a} {b}\n")

        proc = subprocess.run(
            [APP, input_path, output_path], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert proc.returncode == 0, f"math_app failed on valid queries: {proc.stderr}"
        assert os.path.isfile(output_path), "math_app did not create its requested output file."

        with open(output_path, "r") as f:
            lines = f.read().strip().splitlines()
        assert len(lines) == len(expected), "math_app produced the wrong number of output lines."
        try:
            actual = [int(line.strip()) for line in lines]
        except ValueError as exc:
            pytest.fail(f"math_app produced a non-integer output: {exc}")
        assert actual == expected, f"math_app produced incorrect LCM results: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
