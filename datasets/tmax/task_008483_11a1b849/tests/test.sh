#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import tempfile

import pytest

BIN = "/home/user/bin/pdf_eval"
INTEGRATE = "/home/user/scripts/integrate.sh"
MONTE_CARLO = "/home/user/scripts/monte_carlo.sh"
INTEGRAL_OUT = "/home/user/data/integral.txt"
MC_OUT = "/home/user/data/mc_area.txt"


def run_script(path, timeout=240):
    result = subprocess.run(
        [path], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f"{path} failed with exit status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_float(path):
    assert os.path.isfile(path), f"Output file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} is not a valid float: '{content}'")
    assert math.isfinite(value), f"Content of {path} is not finite: '{content}'"
    return value


def test_pdf_eval_compiled_and_executable():
    executable_path = BIN
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pdf_eval must be a compiled ELF executable."

    for x in (-2.375, -0.41, 0.0, 1.2345, 2.81):
        result = subprocess.run(
            [BIN, str(x)], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, f"pdf_eval failed for x={x}: {result.stderr}"
        try:
            actual = float(result.stdout.strip())
        except ValueError:
            pytest.fail(f"pdf_eval returned a non-numeric value for x={x}: {result.stdout!r}")
        expected = math.exp(-x*x / 2.0) * (1.0 + math.sin(5.0*x) ** 2)
        assert abs(actual - expected) <= 1.1e-6, (
            f"pdf_eval({x}) returned {actual}, expected {expected}"
        )


def test_scripts_exist_and_executable():
    for script in (INTEGRATE, MONTE_CARLO):
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."
        with open(script, "r", errors="replace") as f:
            lines = f.readlines()
        assert lines and "bash" in lines[0].lower(), f"{script} must be a Bash script."
        for line in lines[1:]:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            assert not re.search(
                r"(?:^|[;&|]\s*)(?:command\s+)?(?:/usr/bin/|/usr/local/bin/)?"
                r"(?:python(?:[23](?:\.\d+)*)?|pypy|Rscript|ruby|perl|node)(?:\s|$)",
                stripped,
            ), f"High-level language invocation is not allowed in {script}: {stripped}"


def test_scripts_execute_and_create_valid_outputs():
    for path in (INTEGRAL_OUT, MC_OUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_script(INTEGRATE)
    val = read_float(INTEGRAL_OUT)
    assert 3.74 < val < 3.77, (
        f"Integral value {val} is not within the expected range (3.74, 3.77)."
    )

    run_script(MONTE_CARLO)
    val = read_float(MC_OUT)
    assert 3.4 < val < 4.1, (
        f"Monte Carlo area estimate {val} is not within the expected range (3.4, 4.1)."
    )


def test_integration_and_sampling_algorithms_are_exercised():
    rng = random.SystemRandom()
    target = rng.uniform(3.745, 3.765)
    quadratic = rng.uniform(0.012, 0.026)
    linear = rng.uniform(-0.035, 0.035)

    # Choose the constant so the exact 1000-interval trapezoidal result is target.
    h = 6.0 / 1000.0
    grid = [-3.0 + i*h for i in range(1001)]
    trap_x2 = h * (0.5*grid[0]**2 + sum(x*x for x in grid[1:-1]) + 0.5*grid[-1]**2)
    constant = (target - quadratic*trap_x2) / 6.0

    work = tempfile.mkdtemp(prefix="verifier_pdf_")
    log_path = os.path.join(work, "calls.txt")
    shim_c = os.path.join(work, "shim.c")
    shim_bin = os.path.join(work, "pdf_eval_shim")
    backup = os.path.join(work, "pdf_eval.original")

    source = r'''#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char *end = NULL;
    double x = strtod(argv[1], &end);
    if (end == argv[1] || *end != '\0') return 3;
    FILE *fp = fopen("%s", "a");
    if (!fp) return 4;
    fprintf(fp, "%%.17g\n", x);
    fclose(fp);
    double y = %.17g + %.17g*x + %.17g*x*x;
    printf("%%.12f\n", y);
    return 0;
}
''' % (log_path, constant, linear, quadratic)

    with open(shim_c, "w") as f:
        f.write(source)
    built = subprocess.run(
        ["gcc", "-O2", shim_c, "-o", shim_bin], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert built.returncode == 0, f"Verifier could not build instrumentation shim: {built.stderr}"

    shutil.copy2(BIN, backup)
    try:
        shutil.copy2(shim_bin, BIN)
        os.chmod(BIN, 0o755)

        open(log_path, "w").close()
        try:
            os.remove(INTEGRAL_OUT)
        except FileNotFoundError:
            pass
        run_script(INTEGRATE)
        integrated = read_float(INTEGRAL_OUT)
        with open(log_path, "r") as f:
            integral_calls = [float(line.strip()) for line in f if line.strip()]

        assert len(integral_calls) == 1001, (
            f"integrate.sh must make exactly 1001 PDF evaluations; made {len(integral_calls)}"
        )
        for actual_x, expected_x in zip(sorted(integral_calls), grid):
            assert abs(actual_x - expected_x) <= 1e-8, (
                "integrate.sh did not evaluate exactly the 1001-point grid from -3 to 3 "
                "with 1000 equal intervals."
            )
        expected_trap = h * (
            0.5*(constant + linear*grid[0] + quadratic*grid[0]**2)
            + sum(constant + linear*x + quadratic*x*x for x in grid[1:-1])
            + 0.5*(constant + linear*grid[-1] + quadratic*grid[-1]**2)
        )
        assert abs(integrated - expected_trap) <= 2e-5, (
            f"integrate.sh returned {integrated}; the required trapezoidal result is {expected_trap}"
        )

        open(log_path, "w").close()
        try:
            os.remove(MC_OUT)
        except FileNotFoundError:
            pass
        run_script(MONTE_CARLO)
        estimate = read_float(MC_OUT)
        with open(log_path, "r") as f:
            mc_calls = [float(line.strip()) for line in f if line.strip()]

        assert len(mc_calls) == 10000, (
            f"monte_carlo.sh must make exactly 10,000 PDF evaluations; made {len(mc_calls)}"
        )
        assert all(math.isfinite(x) and -3.0 <= x <= 3.0 for x in mc_calls), (
            "Monte Carlo x coordinates must all lie in [-3, 3]."
        )
        assert min(mc_calls) < -2.8 and max(mc_calls) > 2.8, (
            "Monte Carlo x coordinates do not span the required uniform range."
        )
        assert abs(sum(mc_calls) / len(mc_calls)) < 0.10, (
            "Monte Carlo x coordinates are not consistent with uniform sampling on [-3, 3]."
        )
        bins = [0] * 10
        for x in mc_calls:
            index = min(9, int((x + 3.0) / 0.6))
            bins[index] += 1
        assert all(800 <= count <= 1200 for count in bins), (
            f"Monte Carlo x coordinates are not uniformly distributed across the box: {bins}"
        )

        expected_area = 6.0*constant + 18.0*quadratic
        assert abs(estimate - expected_area) <= 0.25, (
            f"Monte Carlo result {estimate} is inconsistent with rejection sampling in the "
            f"specified 6-by-2 bounding box; expected approximately {expected_area}."
        )
        scaled_hits = estimate * 10000.0 / 12.0
        assert abs(scaled_hits - round(scaled_hits)) <= 0.02, (
            "Monte Carlo area must be computed as 12 * hits / 10000."
        )
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, BIN)
            os.chmod(BIN, 0o755)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
