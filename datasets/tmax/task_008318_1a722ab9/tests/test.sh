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
import pytest

SOLVER_C = "/home/user/solver.c"
SCRIPT = "/home/user/orchestrate.sh"
DATASET = "/home/user/dataset.csv"
RESULTS = "/home/user/ci_results.txt"


def run_orchestrate():
    result = subprocess.run(
        [SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, (
        f"orchestrate.sh failed with return code {result.returncode}.\n"
        f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
    )


def parse_ci(strict=False):
    assert os.path.isfile(RESULTS), f"{RESULTS} does not exist. The script failed to create it."
    with open(RESULTS, "r") as f:
        content = f.read()

    lower_match = re.search(r"Lower CI:\s*([\d.]+)", content)
    upper_match = re.search(r"Upper CI:\s*([\d.]+)", content)
    assert lower_match is not None, f"Could not find 'Lower CI: <value>' in {RESULTS}. Content:\n{content}"
    assert upper_match is not None, f"Could not find 'Upper CI: <value>' in {RESULTS}. Content:\n{content}"

    try:
        lower = float(lower_match.group(1))
        upper = float(upper_match.group(1))
    except ValueError:
        pytest.fail("Parsed CI values are not valid floats.")

    if strict:
        assert re.fullmatch(
            r"Lower CI: -?\d+\.\d{4}\nUpper CI: -?\d+\.\d{4}\n?", content
        ), f"CI output does not have the required exact two-line, four-decimal format:\n{content}"
    return lower, upper


def test_solver_c_exists():
    assert os.path.isfile(SOLVER_C), f"{SOLVER_C} does not exist."


def test_orchestrate_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_orchestrate_sh_execution():
    run_orchestrate()


def test_ci_results():
    lower_ci, upper_ci = parse_ci()
    assert 1.9000 <= lower_ci <= 1.9500, f"Lower CI {lower_ci} is out of the expected range [1.9000, 1.9500]"
    assert 2.0200 <= upper_ci <= 2.0700, f"Upper CI {upper_ci} is out of the expected range [2.0200, 2.0700]"


def trap_target(a, b, c, x):
    # Exact value of the composite trapezoidal sum for this quadratic at N=1000.
    n = 1000.0
    return a * x**3 * (1.0 / 3.0 + 1.0 / (6.0 * n * n)) + b * x*x / 2.0 + c*x


def prescribed_root(a, b, c, target):
    x = 1.0
    for _ in range(50):
        dx = x / 1000.0
        total = 0.0
        for i in range(1000):
            t1 = i * dx
            t2 = (i + 1) * dx
            y1 = a*t1*t1 + b*t1 + c
            y2 = a*t2*t2 + b*t2 + c
            total += 0.5 * (y1 + y2) * dx
        fv = total - target
        if abs(fv) < 1e-5:
            break
        x -= fv / (a*x*x + b*x + c)
    return x


def binomial_quantile(n, p, q):
    cumulative = 0.0
    for k in range(n + 1):
        cumulative += math.comb(n, k) * (p**k) * ((1.0-p)**(n-k))
        if cumulative >= q:
            return k
    return n


def make_two_point_dataset(low, high, high_count):
    rows = []
    for i in range(100):
        x = high if i < high_count else low
        # Vary coefficients so the workflow cannot infer roots from row positions alone.
        a = 0.65 + (i % 11) * 0.047
        b = 1.10 + (i % 7) * 0.083
        c = 2.20 + (i % 13) * 0.061
        target = trap_target(a, b, c, x)
        rows.append(f"{a:.10f},{b:.10f},{c:.10f},{target:.10f}\n")
    random.SystemRandom().shuffle(rows)
    with open(DATASET, "w") as f:
        f.writelines(rows)


def check_bootstrap_scenario(low, high, high_count):
    make_two_point_dataset(low, high, high_count)
    try:
        os.remove("/home/user/solver")
    except FileNotFoundError:
        pass
    run_orchestrate()

    solver = "/home/user/solver"
    assert os.path.isfile(solver), "orchestrate.sh did not create /home/user/solver"
    assert os.access(solver, os.X_OK), "The compiled solver is not executable"
    with open(solver, "rb") as f:
        assert f.read(4) == b"\x7fELF", "orchestrate.sh did not produce a compiled native solver executable"

    lower, upper = parse_ci(strict=True)
    assert lower <= upper, f"Invalid confidence interval: {lower} > {upper}"

    p = high_count / 100.0
    # A correct 1000-replicate bootstrap almost certainly has its empirical
    # 25th and 975th order statistics inside these conservative population bands.
    lower_k_min = binomial_quantile(100, p, 0.005)
    lower_k_max = binomial_quantile(100, p, 0.070)
    upper_k_min = binomial_quantile(100, p, 0.930)
    upper_k_max = binomial_quantile(100, p, 0.995)

    def sample_mean(k):
        return low + (high-low) * k / 100.0

    lo_min, lo_max = sample_mean(lower_k_min), sample_mean(lower_k_max)
    hi_min, hi_max = sample_mean(upper_k_min), sample_mean(upper_k_max)
    assert lo_min - 0.0002 <= lower <= lo_max + 0.0002, (
        f"Lower CI {lower} is inconsistent with bootstrap resampling; expected "
        f"approximately [{lo_min:.4f}, {lo_max:.4f}]"
    )
    assert hi_min - 0.0002 <= upper <= hi_max + 0.0002, (
        f"Upper CI {upper} is inconsistent with bootstrap resampling; expected "
        f"approximately [{hi_min:.4f}, {hi_max:.4f}]"
    )


def test_dynamic_solver_and_bootstrap_behavior():
    backup = "/tmp/original_dataset.csv"
    shutil.copyfile(DATASET, backup)
    rng = random.SystemRandom()
    try:
        # Two unpredictable, disjoint distributions reject fixed CI output and
        # exercise sampling with replacement and percentile selection.
        low1 = round(rng.uniform(0.55, 0.85), 4)
        high1 = round(rng.uniform(2.20, 2.90), 4)
        check_bootstrap_scenario(low1, high1, rng.randint(10, 20))

        low2 = round(rng.uniform(3.20, 3.80), 4)
        high2 = round(rng.uniform(6.10, 6.80), 4)
        check_bootstrap_scenario(low2, high2, rng.randint(20, 35))

        # Directly exercise the compiled C program on values derived using the
        # required 1000-panel trapezoidal rule and Newton iteration. Large-x
        # cases make analytical integration or a different panel count visible
        # even after four-decimal formatting.
        cases = [
            (0.7, 1.3, 2.1, 3.7),
            (1.4, 2.6, 4.2, 17.9),
            (0.55, 1.05, 3.8, 0.8),
            (1.2, 1.8, 2.7, 75.0),
        ]
        for x in (420.1234, 600.1234, 735.4321):
            a, b, c = 1.0, 0.0, 120000.0
            cases.append((a, b, c, trap_target(a, b, c, x)))

        rows = []
        expected = []
        for i in range(100):
            a, b, c, target = cases[i % len(cases)]
            line = f"{a:.10f},{b:.10f},{c:.10f},{target:.10f}"
            aa, bb, cc, tt = map(float, line.split(","))
            rows.append(line + "\n")
            expected.append(f"{prescribed_root(aa, bb, cc, tt):.4f}")
        with open(DATASET, "w") as f:
            f.writelines(rows)

        result = subprocess.run(
            ["/home/user/solver"], cwd="/home/user", capture_output=True,
            text=True, timeout=60
        )
        assert result.returncode == 0, f"solver failed:\n{result.stderr}"
        actual = result.stdout.splitlines()
        assert len(actual) == 100, f"solver printed {len(actual)} lines instead of 100"
        assert all(re.fullmatch(r"-?\d+\.\d{4}", line) for line in actual), (
            "Every solver result must be printed with exactly four decimal places"
        )
        assert actual == expected, (
            "solver output does not match Newton's method using the required "
            "1000-interval trapezoidal integral"
        )
    finally:
        shutil.copyfile(backup, DATASET)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
