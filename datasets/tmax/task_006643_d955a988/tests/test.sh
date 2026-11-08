#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

REPO = "/home/user/service_repo"
SOURCE = os.path.join(REPO, "poly_math.c")
SERVICE = os.path.join(REPO, "math_service")
RESULTS = os.path.join(REPO, "results.txt")


def run_checked(command, cwd=REPO, timeout=30):
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_00_compile_and_exercise_poly_math_source():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist. The file was not properly recovered."
    assert os.path.isfile(SERVICE), f"{SERVICE} does not exist. The service was not compiled."
    assert os.access(SERVICE, os.X_OK), f"{SERVICE} is not executable."

    # Exercise compute_polynomial_roots independently on verifier-selected inputs.
    harness_source = r'''#include <stdio.h>

double compute_polynomial_roots(int degree, double *coefficients);

int main(void) {
    double a[] = {4.0, 100.0};
    double b[] = {-2.0, 3.5, 99.0};
    double c[] = {2.0, -5.0, 4.0, -1.0, 0.5, -0.1};

    printf("%.12f\n", compute_polynomial_roots(1, a));
    printf("%.12f\n", compute_polynomial_roots(2, b));
    printf("%.12f\n", compute_polynomial_roots(5, c));
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_c = os.path.join(td, "harness.c")
        harness_bin = os.path.join(td, "harness")
        with open(harness_c, "w") as f:
            f.write(harness_source)

        run_checked([
            "gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
            harness_c, SOURCE, "-lm", "-o", harness_bin,
        ])
        result = run_checked([harness_bin])
        values = [float(line) for line in result.stdout.splitlines() if line.strip()]
        expected = [0.15 * 4.0, 0.15 * (-2.0 + 3.5), 0.15 * (2.0 - 5.0 + 4.0 - 1.0 + 0.5)]
        assert len(values) == len(expected), f"Unexpected harness output: {result.stdout!r}"
        for actual, wanted in zip(values, expected):
            assert abs(actual - wanted) < 1e-10, (
                f"compute_polynomial_roots changed program logic: got {actual}, expected {wanted}"
            )

    # Build the actual service from the submitted source with strict warning checks.
    rebuilt = os.path.join(REPO, ".math_service.verifier")
    try:
        run_checked([
            "gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
            os.path.join(REPO, "main.c"), SOURCE, "-lm", "-o", rebuilt,
        ])
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
        os.replace(rebuilt, SERVICE)
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)

    # Discard any fabricated/stale results and generate them with the rebuilt service.
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    run_checked(["./math_service"])
    assert os.path.isfile(RESULTS), "The rebuilt service did not create results.txt."
    with open(RESULTS, "r") as f:
        generated = f.read().strip()
    assert generated == "Final Sum: 750.00", f"Unexpected generated output: {generated!r}"


def test_poly_math_c_exists():
    path = "/home/user/service_repo/poly_math.c"
    assert os.path.isfile(path), f"{path} does not exist. The file was not properly recovered."


def test_math_service_executable():
    path = "/home/user/service_repo/math_service"
    assert os.path.isfile(path), f"{path} does not exist. The service was not compiled."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_results_txt():
    path = "/home/user/service_repo/results.txt"
    assert os.path.isfile(path), f"{path} does not exist. Did you run the compiled executable?"
    with open(path, "r") as f:
        content = f.read().strip()

    # The unmodified math logic produces 750.00
    assert "Final Sum: 750.00" in content, f"Unexpected content in results.txt: '{content}'. The math logic might have been altered."


def test_leak_report():
    path = "/home/user/leak_report.txt"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # The original leak is on line 9
    match = re.search(r"(?i)line[\s:]*9\b", content)
    assert match is not None, f"Leak report does not contain the correct line number (9). Content found: '{content.strip()}'"


def test_valgrind_no_leaks():
    executable_path = "/home/user/service_repo/math_service"
    assert os.path.exists(executable_path), "Cannot run valgrind because math_service is missing."

    result = subprocess.run(
        ["valgrind", "--leak-check=full", "--error-exitcode=99", "./math_service"],
        cwd="/home/user/service_repo",
        capture_output=True,
        text=True,
        timeout=60,
    )

    # Valgrind outputs its memory check report to stderr
    output = result.stderr
    assert result.returncode == 0, f"Valgrind or math_service failed:\n{output}"
    assert "definitely lost: 0 bytes in 0 blocks" in output, "Memory leak detected by valgrind. The leak in poly_math.c was not fully resolved."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
