#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pytest
from scipy.integrate import solve_ivp

AGENT_BIN = "/home/user/classifier"
CLEAN_DIR = "/verify/corpus/clean"
EVIL_DIR = "/verify/corpus/evil"


def run_classifier(csv_file):
    return subprocess.run(
        [AGENT_BIN, csv_file],
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), f"The agent binary is missing at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"The agent binary at {AGENT_BIN} is not executable"


def test_classifier_clean_corpus():
    clean_files = sorted(glob.glob(os.path.join(CLEAN_DIR, "*.csv")))
    assert len(clean_files) > 0, f"No clean CSV files found in {CLEAN_DIR}"

    failed_files = []
    for csv_file in clean_files:
        result = run_classifier(csv_file)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected "
            f"(should be CLEAN, exit 0). Offending files: {', '.join(failed_files)}"
        )


def test_classifier_evil_corpus():
    evil_files = sorted(glob.glob(os.path.join(EVIL_DIR, "*.csv")))
    assert len(evil_files) > 0, f"No evil CSV files found in {EVIL_DIR}"

    failed_files = []
    for csv_file in evil_files:
        result = run_classifier(csv_file)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "EVIL":
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil files bypassed "
            f"(should be EVIL, exit 1). Offending files: {', '.join(failed_files)}"
        )


def physical_checks(t, x, y):
    integral = 0.0
    kinematic_ok = True
    for i in range(1, len(t)):
        integral += 0.5 * (y[i - 1] + y[i]) * (t[i] - t[i - 1])
        if abs(integral - (x[i] - x[0])) >= 0.05:
            kinematic_ok = False

    # This is the quantity implemented by the supplied black-box oracle.
    q = 0.5 * y * y + 1.5 * x ** 4 - 2.0 * x * x
    conservation_ok = float(np.var(q)) < 0.001
    return kinematic_ok, conservation_ok


def solve_trajectory(rng, damped=False):
    duration = rng.uniform(5.5, 7.5)
    count = rng.randrange(241, 301)
    t = np.linspace(0.0, duration, count)
    x0 = rng.uniform(0.9, 1.4)
    y0 = rng.uniform(-0.45, 0.45)
    damping = rng.uniform(0.30, 0.50) if damped else 0.0

    def deriv(_, state):
        x, y = state
        return (y, 4.0 * x - 6.0 * x ** 3 - damping * y)

    solution = solve_ivp(
        deriv,
        (0.0, duration),
        (x0, y0),
        t_eval=t,
        rtol=1e-10,
        atol=1e-12,
        method="DOP853",
    )
    assert solution.success
    return t, solution.y[0], solution.y[1]


def make_case(rng, kind):
    for _ in range(100):
        t, x, y = solve_trajectory(rng, damped=(kind == "damped"))
        if kind == "warped":
            t = t * rng.uniform(1.35, 1.75)

        kinematic_ok, conservation_ok = physical_checks(t, x, y)
        if kind == "clean" and kinematic_ok and conservation_ok:
            return t, x, y, "CLEAN", 0
        if kind == "warped" and not kinematic_ok and conservation_ok:
            return t, x, y, "EVIL", 1
        if kind == "damped" and kinematic_ok and not conservation_ok:
            return t, x, y, "EVIL", 1

    raise AssertionError(f"Could not generate a well-separated {kind} test case")


def write_csv(path, t, x, y):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(("t", "x", "y"))
        for row in zip(t, x, y):
            writer.writerow((format(float(row[0]), ".17g"),
                             format(float(row[1]), ".17g"),
                             format(float(row[2]), ".17g")))


def test_randomized_content_based_classification():
    rng = secrets.SystemRandom()
    kinds = ["clean"] * 5 + ["warped"] * 4 + ["damped"] * 4
    rng.shuffle(kinds)

    with tempfile.TemporaryDirectory(prefix="trajectory_inputs_") as directory:
        cases = []
        for kind in kinds:
            t, x, y, expected_output, expected_status = make_case(rng, kind)
            # Every class uses the same directory and indistinguishable random names.
            path = os.path.join(directory, secrets.token_hex(16) + ".csv")
            write_csv(path, t, x, y)
            cases.append((path, expected_output, expected_status))

        rng.shuffle(cases)
        failures = []
        for path, expected_output, expected_status in cases:
            result = run_classifier(path)
            if result.returncode != expected_status or result.stdout.strip() != expected_output:
                failures.append(
                    f"{os.path.basename(path)} expected {expected_output}/exit {expected_status}, "
                    f"got {result.stdout.strip()!r}/exit {result.returncode}"
                )

        if failures:
            pytest.fail("Randomized trajectory failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
