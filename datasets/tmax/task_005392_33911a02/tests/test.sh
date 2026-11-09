#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import stat
import subprocess

import pytest

PROJECT_DIR = "/home/user/sim_project"
PROFILE_SCRIPT = os.path.join(PROJECT_DIR, "profile_runs.sh")
STABLE_TIMES_FILE = os.path.join(PROJECT_DIR, "stable_times.txt")
BOOTSTRAP_SCRIPT = os.path.join(PROJECT_DIR, "bootstrap_ci.sh")
CI_RESULTS_FILE = os.path.join(PROJECT_DIR, "ci_results.txt")
NOTEBOOK = os.path.join(PROJECT_DIR, "experiment_workflow.ipynb")
INTEGRATOR = os.path.join(PROJECT_DIR, "integrator.sh")


def run_script(path, timeout=20):
    return subprocess.run(
        [path], cwd=PROJECT_DIR, text=True, capture_output=True,
        timeout=timeout, check=False
    )


def read_numeric_lines(path):
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    return [float(line) for line in lines]


def read_ci(strict=False):
    with open(CI_RESULTS_FILE, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) == 2
    pattern = r"^Lower CI: (-?[0-9]+\.[0-9]{2})$" if strict else r"^Lower CI:\s*([0-9.]+)$"
    lower = re.match(pattern, lines[0])
    pattern = r"^Upper CI: (-?[0-9]+\.[0-9]{2})$" if strict else r"^Upper CI:\s*([0-9.]+)$"
    upper = re.match(pattern, lines[1])
    assert lower and upper
    return float(lower.group(1)), float(upper.group(1))


# Original assertions.
def test_profile_script_exists():
    assert os.path.isfile(PROFILE_SCRIPT), f"File {PROFILE_SCRIPT} does not exist."
    assert os.access(PROFILE_SCRIPT, os.X_OK), f"File {PROFILE_SCRIPT} is not executable."


def test_bootstrap_script_exists():
    assert os.path.isfile(BOOTSTRAP_SCRIPT), f"File {BOOTSTRAP_SCRIPT} does not exist."
    assert os.access(BOOTSTRAP_SCRIPT, os.X_OK), f"File {BOOTSTRAP_SCRIPT} is not executable."


def test_stable_times_file_exists_and_valid():
    assert os.path.isfile(STABLE_TIMES_FILE), f"File {STABLE_TIMES_FILE} does not exist."
    with open(STABLE_TIMES_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"File {STABLE_TIMES_FILE} is empty."

    for line in lines:
        try:
            val = float(line)
            assert val > 0, f"Stable time {val} should be positive."
        except ValueError:
            pytest.fail(f"Invalid non-numeric value found in {STABLE_TIMES_FILE}: {line}")


def test_ci_results_format_and_values():
    assert os.path.isfile(CI_RESULTS_FILE), f"File {CI_RESULTS_FILE} does not exist."

    with open(CI_RESULTS_FILE, 'r') as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) == 2, f"{CI_RESULTS_FILE} must contain exactly two lines."

    lower_match = re.match(r"^Lower CI:\s*([0-9.]+)$", lines[0])
    upper_match = re.match(r"^Upper CI:\s*([0-9.]+)$", lines[1])

    assert lower_match, f"First line of {CI_RESULTS_FILE} is malformed. Expected 'Lower CI: <value>'."
    assert upper_match, f"Second line of {CI_RESULTS_FILE} is malformed. Expected 'Upper CI: <value>'."

    lower_val = float(lower_match.group(1))
    upper_val = float(upper_match.group(1))

    assert lower_val <= upper_val, "Lower CI must be less than or equal to Upper CI."
    assert 40 <= lower_val <= 150, f"Lower CI {lower_val} is outside the plausible range (40-150 ms)."
    assert 40 <= upper_val <= 150, f"Upper CI {upper_val} is outside the plausible range (40-150 ms)."


# Execute profile_runs.sh against a fresh notebook and a logging integrator.
def test_profile_script_extracts_runs_and_filters_by_exit_status(tmp_path):
    rng = random.SystemRandom()
    stable = [round(rng.uniform(0.02, 0.42), 3) for _ in range(4)]
    divergent = [round(rng.uniform(0.58, 1.25), 3) for _ in range(3)]
    steps = stable + divergent
    rng.shuffle(steps)

    notebook_data = {
        "cells": [{
            "cell_type": "code",
            "execution_count": 1,
            "metadata": {},
            "outputs": [],
            "source": ["# Dynamically supplied parameters\n", "STEP_SIZES = [" + ", ".join(map(str, steps)) + "]"]
        }],
        "metadata": {}, "nbformat": 4, "nbformat_minor": 5
    }

    log_path = tmp_path / "calls.log"
    notebook_bytes = open(NOTEBOOK, "rb").read()
    integrator_bytes = open(INTEGRATOR, "rb").read()
    integrator_mode = stat.S_IMODE(os.stat(INTEGRATOR).st_mode)

    wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {str(log_path)!r}
if awk -v x="$1" 'BEGIN {{ exit !(x >= 0.5) }}'; then
    sleep 0.01
    echo DIVERGENCE
    exit 1
fi
sleep 0.04
echo SUCCESS
exit 0
'''

    try:
        with open(NOTEBOOK, "w") as f:
            json.dump(notebook_data, f)
        with open(INTEGRATOR, "w") as f:
            f.write(wrapper)
        os.chmod(INTEGRATOR, 0o755)

        result = run_script(PROFILE_SCRIPT)
        assert result.returncode == 0, result.stdout + result.stderr
        assert log_path.exists(), "profile_runs.sh did not execute ./integrator.sh"
        calls = [float(x) for x in log_path.read_text().splitlines() if x.strip()]
        times = read_numeric_lines(STABLE_TIMES_FILE)
    finally:
        with open(NOTEBOOK, "wb") as f:
            f.write(notebook_bytes)
        with open(INTEGRATOR, "wb") as f:
            f.write(integrator_bytes)
        os.chmod(INTEGRATOR, integrator_mode)

    assert calls == steps, f"Expected one integrator call per extracted STEP_SIZES value; got {calls}"
    expected_stable = sum(x < 0.5 for x in steps)
    assert len(times) == expected_stable, "Failed runs were retained or successful runs were omitted"
    assert all(25 <= x <= 250 for x in times), "Recorded values are not plausible elapsed milliseconds"

    # Also exercise the script with the supplied workflow and integrator.
    result = run_script(PROFILE_SCRIPT)
    assert result.returncode == 0, result.stdout + result.stderr
    assert len(read_numeric_lines(STABLE_TIMES_FILE)) == 7


# Execute bootstrap_ci.sh on data whose bootstrap percentiles are independently known.
def test_bootstrap_script_computes_resampled_mean_interval():
    source = open(BOOTSTRAP_SCRIPT, "r").read()
    assert re.search(r"(?<![0-9])1000(?![0-9])", source), "Bootstrap script must perform 1,000 resamples"

    rng = random.SystemRandom()
    low = round(rng.uniform(50.00, 59.00), 2)
    high = round(rng.uniform(101.00, 114.00), 2)

    # With N=2 and 1,000 samples, the requested tails are the two endpoints.
    with open(STABLE_TIMES_FILE, "w") as f:
        f.write(f"{low:.2f}\n{high:.2f}\n")
    result = run_script(BOOTSTRAP_SCRIPT)
    assert result.returncode == 0, result.stdout + result.stderr
    lower, upper = read_ci(strict=True)
    assert lower == pytest.approx(low, abs=0.01)
    assert upper == pytest.approx(high, abs=0.01)

    # For ten copies of each endpoint (N=20), the mean-bootstrap interval is
    # interior to the endpoints and concentrated near 30% and 70% of the span.
    with open(STABLE_TIMES_FILE, "w") as f:
        for value in ([low] * 10 + [high] * 10):
            f.write(f"{value:.2f}\n")
    result = run_script(BOOTSTRAP_SCRIPT)
    assert result.returncode == 0, result.stdout + result.stderr
    lower, upper = read_ci(strict=True)
    span = high - low
    assert low + 0.15 * span <= lower <= low + 0.40 * span
    assert low + 0.60 * span <= upper <= low + 0.85 * span
    assert lower < upper
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
