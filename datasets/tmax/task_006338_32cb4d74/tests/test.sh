#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

BASE_DIR = "/home/user/calc_engine"
LOG_PATH = "/home/user/results.log"
DATA_PATH = os.path.join(BASE_DIR, "data.txt")
CONFIG_PATH = os.path.join(BASE_DIR, "config.h")
MAKEFILE_PATH = os.path.join(BASE_DIR, "Makefile")
SOLVER_PATH = os.path.join(BASE_DIR, "solver.c")
BINARY_PATH = os.path.join(BASE_DIR, "solver")

ORIGINAL_DATA = b"10.5\n20.1\nN/A\n5.0\nERR_TIMEOUT\n30.2\n"
ORIGINAL_VALUES = [10.5, 20.1, 5.0, 30.2]


def solve_py(val, coeff=15.420):
    x = 1.0
    for _ in range(1000):
        err = x * math.exp(x) - (val + coeff)
        if abs(err) <= 1e-12:
            break
        x -= err / (math.exp(x) * (1.0 + x))
    return x


def expected_output(values):
    return f"Total Sum: {sum(solve_py(v) for v in values):.5f}\n"


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile missing at {MAKEFILE_PATH}"
    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not contain the '-lm' linker flag."


def test_config_fixed():
    assert os.path.isfile(CONFIG_PATH), f"config.h missing at {CONFIG_PATH}"
    with open(CONFIG_PATH, "r") as f:
        content = f.read()
    assert "15.42" in content, "config.h does not contain the recovered MAGIC_COEFF (15.420)."


def test_solver_c_convergence_fixed():
    assert os.path.isfile(SOLVER_PATH), f"solver.c missing at {SOLVER_PATH}"
    with open(SOLVER_PATH, "r") as f:
        content = f.read()
    assert "abs(" in content or "err < -1e-6" in content, "solver.c does not seem to fix the convergence logic by taking the absolute value of err."


def test_results_log_exists():
    assert os.path.isfile(LOG_PATH), f"Results log missing at {LOG_PATH}"


def test_results_log_correctness():
    assert os.path.isfile(LOG_PATH), f"Results log missing at {LOG_PATH}"
    assert os.path.isfile(DATA_PATH), f"data.txt missing at {DATA_PATH}"

    with open(DATA_PATH, "r") as f:
        tokens = f.read().split()

    valid_vals = []
    for token in tokens:
        try:
            valid_vals.append(float(token))
        except ValueError:
            pass

    def original_solve_py(val, coeff=15.420):
        x = 1.0
        def f(x): return x * math.exp(x) - (val + coeff)
        def df(x): return math.exp(x) * (1.0 + x)
        err = f(x)
        iter_count = 0
        while abs(err) > 1e-6 and iter_count < 1000:
            x = x - err / df(x)
            err = f(x)
            iter_count += 1
        return x

    expected_sum = sum(original_solve_py(v) for v in valid_vals)
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    match = re.search(r"Total Sum:\s*([0-9.]+)", log_content)
    assert match is not None, f"Could not find 'Total Sum: <value>' in {LOG_PATH}. File content: {log_content}"
    actual_sum = float(match.group(1))
    assert math.isclose(actual_sum, expected_sum, rel_tol=1e-3), \
        f"Expected total sum to be approximately {expected_sum:.5f}, but got {actual_sum}. Check input parsing and convergence logic."


def test_original_input_and_exact_saved_output():
    with open(DATA_PATH, "rb") as f:
        assert f.read() == ORIGINAL_DATA, "data.txt was modified instead of fixing the parser"
    with open(LOG_PATH, "r") as f:
        actual = f.read()
    assert actual == expected_output(ORIGINAL_VALUES), \
        f"results.log must contain the exact solver output for the supplied data; got {actual!r}"


def test_project_builds_and_solver_handles_unseen_corrupt_input():
    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)

    build = subprocess.run(
        ["make", "-B", "solver"], cwd=BASE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(BINARY_PATH), "make did not create the solver executable"
    assert os.access(BINARY_PATH, os.X_OK), "solver is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "solver is not a compiled executable"

    rng = random.SystemRandom()
    random_values = [rng.uniform(0.25, 95.0) for _ in range(7)]
    cases = [
        ([10.5, 20.1, 5.0, 30.2],
         "10.5\n20.1\nN/A\n5.0\nERR_TIMEOUT\n30.2\n"),
        (random_values,
         (f"{random_values[0]:.12f}\nERR\n"
          f"{random_values[1]:.12f}\nNaN\nrandom_text\n"
          f"{random_values[2]:.12f}\n12oops\n"
          + "\n".join(f"{v:.12f}" for v in random_values[3:]) + "\n")),
    ]
    # Values are serialized before computing the oracle so both sides receive
    # exactly the same floating-point inputs.
    cases[1] = ([float(f"{v:.12f}") for v in random_values], cases[1][1])

    with open(DATA_PATH, "rb") as f:
        saved_data = f.read()
    try:
        for values, contents in cases:
            with open(DATA_PATH, "w") as f:
                f.write(contents)
            run = subprocess.run(
                [BINARY_PATH], cwd=BASE_DIR,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=10
            )
            assert run.returncode == 0, f"solver exited {run.returncode}: {run.stderr}"
            assert run.stderr == "", f"solver wrote unexpected stderr: {run.stderr!r}"
            expected = expected_output(values)
            assert run.stdout == expected, \
                f"solver output was {run.stdout!r}, expected {expected!r} for input:\n{contents}"
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(saved_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
