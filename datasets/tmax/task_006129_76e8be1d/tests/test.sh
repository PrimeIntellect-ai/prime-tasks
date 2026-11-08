#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

HOME = "/home/user"
COUNTS_PATH = os.path.join(HOME, "counts.txt")
LOG_PATH = os.path.join(HOME, "analysis.log")
SOURCE_PATH = os.path.join(HOME, "mcmc.cpp")
EXEC_PATH = os.path.join(HOME, "mcmc")

with open(COUNTS_PATH, "r") as f:
    ORIGINAL_COUNTS_TEXT = f.read()


def parse_results(content):
    mean_match = re.search(r"Posterior Mean:\s*(-?\d+\.\d+)", content)
    ll_h0_match = re.search(r"LL H0:\s*(-?\d+\.\d+)", content)
    ll_h1_match = re.search(r"LL H1:\s*(-?\d+\.\d+)", content)

    assert mean_match is not None, "Could not parse 'Posterior Mean: X.XX' from program output"
    assert ll_h0_match is not None, "Could not parse 'LL H0: X.XX' from program output"
    assert ll_h1_match is not None, "Could not parse 'LL H1: X.XX' from program output"

    return tuple(float(m.group(1)) for m in (mean_match, ll_h0_match, ll_h1_match))


def log_likelihood(lam, data):
    return sum(k * math.log(lam) - lam - math.lgamma(k + 1) for k in data)


def run_submission(counts):
    with open(COUNTS_PATH, "w") as f:
        f.write(" ".join(str(k) for k in counts) + "\n")

    if os.path.lexists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        [EXEC_PATH],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"mcmc exited with status {result.returncode}: {result.stderr}"

    if os.path.isfile(LOG_PATH):
        with open(LOG_PATH, "r") as f:
            content = f.read()
    else:
        content = result.stdout
        assert content.strip(), "mcmc produced neither analysis.log nor parseable standard output"
        # This is equivalent to running ./mcmc > analysis.log.
        with open(LOG_PATH, "w") as f:
            f.write(content)

    return parse_results(content)


def check_run(counts):
    mean_val, ll_h0, ll_h1 = run_submission(counts)

    expected_ll_h0 = log_likelihood(3.0, counts)
    expected_ll_h1 = log_likelihood(mean_val, counts)
    # For a uniform prior away from its boundaries, the exact posterior is
    # Gamma(sum(counts)+1, rate=len(counts)). The tolerance permits normal
    # Monte Carlo variation and two-decimal output.
    expected_mean = (sum(counts) + 1.0) / len(counts)

    assert abs(mean_val - expected_mean) <= 0.10, (
        f"Posterior Mean {mean_val} is inconsistent with this input; "
        f"expected an MCMC estimate near {expected_mean:.3f}."
    )
    assert math.isclose(ll_h0, expected_ll_h0, abs_tol=0.1), (
        f"LL H0 {ll_h0} does not match expected {expected_ll_h0:.2f}."
    )
    assert math.isclose(ll_h1, expected_ll_h1, abs_tol=0.1), (
        f"LL H1 {ll_h1} does not match expected {expected_ll_h1:.2f}."
    )


def test_mcmc_files_exist():
    assert os.path.exists(SOURCE_PATH), "/home/user/mcmc.cpp does not exist."
    assert os.path.isfile(SOURCE_PATH), "/home/user/mcmc.cpp is not a regular file."
    assert os.path.exists(EXEC_PATH), "/home/user/mcmc executable does not exist."
    assert os.access(EXEC_PATH, os.X_OK), "/home/user/mcmc is not executable."


def test_rebuild_from_submitted_source():
    # Discard the submitted binary and build exactly from the submitted source.
    if os.path.lexists(EXEC_PATH):
        os.remove(EXEC_PATH)
    subprocess.run(
        ["g++", "-O3", "mcmc.cpp", "-o", "mcmc"],
        cwd=HOME,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert os.path.isfile(EXEC_PATH), "Compilation did not produce /home/user/mcmc."
    assert os.access(EXEC_PATH, os.X_OK), "/home/user/mcmc is not executable after compilation."


def test_executable_on_additional_inputs():
    hidden_inputs = [
        [1, 2, 3, 2, 1, 4, 2, 3, 2, 1, 3, 2, 4, 1, 2, 3, 2, 2, 1, 3],
        [6, 8, 7, 5, 9, 6, 7, 8, 6, 7, 5, 8, 7, 6, 9, 7, 8, 6, 7, 5],
    ]
    try:
        for counts in hidden_inputs:
            check_run(counts)
    finally:
        with open(COUNTS_PATH, "w") as f:
            f.write(ORIGINAL_COUNTS_TEXT)


def test_analysis_log():
    counts = [int(x) for x in ORIGINAL_COUNTS_TEXT.split()]
    run_submission(counts)

    log_path = "/home/user/analysis.log"
    assert os.path.exists(log_path), f"File {log_path} not found."

    with open(log_path, 'r') as f:
        content = f.read()

    mean_match = re.search(r"Posterior Mean:\s*(-?\d+\.\d+)", content)
    ll_h0_match = re.search(r"LL H0:\s*(-?\d+\.\d+)", content)
    ll_h1_match = re.search(r"LL H1:\s*(-?\d+\.\d+)", content)

    assert mean_match is not None, "Could not parse 'Posterior Mean: X.XX' from analysis.log"
    assert ll_h0_match is not None, "Could not parse 'LL H0: X.XX' from analysis.log"
    assert ll_h1_match is not None, "Could not parse 'LL H1: X.XX' from analysis.log"

    mean_val = float(mean_match.group(1))
    ll_h0 = float(ll_h0_match.group(1))
    ll_h1 = float(ll_h1_match.group(1))

    expected_ll_h0 = log_likelihood(3.0, counts)
    expected_ll_h1 = log_likelihood(mean_val, counts)

    # Preserve the original assertions.
    assert 4.70 <= mean_val <= 4.80, f"Posterior Mean {mean_val} is out of expected bounds (4.70 - 4.80)."
    assert math.isclose(ll_h0, expected_ll_h0, abs_tol=0.1), f"LL H0 {ll_h0} does not match expected {expected_ll_h0:.2f}."
    assert math.isclose(ll_h1, expected_ll_h1, abs_tol=0.1), f"LL H1 {ll_h1} does not match expected {expected_ll_h1:.2f}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
