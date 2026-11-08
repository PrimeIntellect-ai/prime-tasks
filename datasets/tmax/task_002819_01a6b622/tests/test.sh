#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

import numpy as np
import pytest

PROJECT = "/home/user/protein"
SOURCE = os.path.join(PROJECT, "simulate.c")
SCRIPT = os.path.join(PROJECT, "test_pipeline.py")
REPORT = os.path.join(PROJECT, "regression_report.log")
SIMULATE = os.path.join(PROJECT, "simulate")


def run_numeric(executable, pdb, seed):
    result = subprocess.run(
        [executable, pdb, str(seed)],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"simulate failed for seed {seed}: {result.stderr}"
    )
    output = result.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), (
        f"simulate must print one numeric mean, got: {output!r}"
    )
    value = float(output)
    assert math.isfinite(value), "simulate returned a non-finite mean"
    return value


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_and_recompute_results(tmp_path_factory):
    assert os.path.isfile(SOURCE), "simulate.c is missing"
    assert os.path.isfile(SCRIPT), "test_pipeline.py is missing"
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, "test_pipeline.py is not executable"

    tempdir = tmp_path_factory.mktemp("behavioral")
    submitted_binary = str(tempdir / "submitted_simulate")
    compile_result = subprocess.run(
        ["gcc", "-o", submitted_binary, SOURCE, "-lgsl", "-lgslcblas", "-lm"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"simulate.c did not compile: {compile_result.stderr}"

    # With exactly two CA atoms, every valid distinct pair has distance 5.  The
    # non-CA atom must be ignored. This derives the answer without trusting the log.
    controlled_pdb = tempdir / "controlled.pdb"
    controlled_pdb.write_text(
        "ATOM      1  CA  GLY A   1       0.000   0.000   0.000  1.00  0.00           C\n"
        "ATOM      2  CA  GLY A   2       3.000   4.000   0.000  1.00  0.00           C\n"
        "ATOM      3  CB  GLY A   3     900.000 900.000 900.000  1.00  0.00           C\n"
    )
    for seed in (1, 17, 50):
        observed = run_numeric(submitted_binary, str(controlled_pdb), seed)
        assert abs(observed - 5.0) <= 1e-6, (
            "simulate did not correctly select distinct CA atoms and compute their distance"
        )

    # Force the Python pipeline to create/compile its own requested executable and
    # regenerate the report during verification.
    if os.path.exists(SIMULATE):
        os.remove(SIMULATE)
    if os.path.exists(REPORT):
        os.remove(REPORT)

    pipeline_result = subprocess.run(
        [SCRIPT],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert pipeline_result.returncode == 0, (
        f"test_pipeline.py failed: stdout={pipeline_result.stdout!r} "
        f"stderr={pipeline_result.stderr!r}"
    )
    assert os.path.isfile(SIMULATE), "test_pipeline.py did not create the simulate executable"
    assert os.access(SIMULATE, os.X_OK), "the generated simulate program is not executable"
    assert os.path.isfile(REPORT), "test_pipeline.py did not generate regression_report.log"

    # Independently exercise the generated simulator on all required seeds. These
    # values are later used to recompute the expected overall mean and bootstrap CI.
    pdb = os.path.join(PROJECT, "1xyz.pdb")
    values = np.array([run_numeric(SIMULATE, pdb, seed) for seed in range(1, 51)], dtype=float)
    assert len(values) == 50
    return values


def test_libgsl_dev_installed():
    """Verify that libgsl-dev is installed."""
    try:
        result = subprocess.run(
            ["dpkg", "-s", "libgsl-dev"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        assert "Status: install ok installed" in result.stdout, "libgsl-dev is not fully installed."
    except subprocess.CalledProcessError:
        pytest.fail("libgsl-dev package is not installed.")


def test_regression_report_exists():
    """Verify that regression_report.log exists."""
    assert os.path.isfile(REPORT), f"Log file {REPORT} does not exist."


def test_regression_report_format_and_values(execute_pipeline_and_recompute_results):
    """Verify the format and contents of regression_report.log."""
    if not os.path.isfile(REPORT):
        pytest.skip("Log file missing.")

    with open(REPORT, "r") as f:
        content = f.read().strip()

    lines = content.split("\n")
    assert len(lines) == 3, "Log file should contain exactly 3 lines."

    mean_match = re.match(r"^Overall Mean:\s*(\d+\.\d{3})$", lines[0])
    assert mean_match is not None, (
        "Line 1 format is incorrect. Expected 'Overall Mean: <mean_rounded_to_3_decimals>'."
    )
    overall_mean = float(mean_match.group(1))
    assert 7.969 <= overall_mean <= 8.369, (
        f"Calculated overall mean {overall_mean} is not within 0.2 of 8.169."
    )

    ci_match = re.match(r"^95% CI:\s*\[(\d+\.\d{3}),\s*(\d+\.\d{3})\]$", lines[1])
    assert ci_match is not None, (
        "Line 2 format is incorrect. Expected "
        "'95% CI: [<lower_rounded_to_3_decimals>, <upper_rounded_to_3_decimals>]'."
    )
    reported_low = float(ci_match.group(1))
    reported_high = float(ci_match.group(2))

    reg_match = re.match(r"^Regression:\s*(PASS|FAIL)$", lines[2])
    assert reg_match is not None, "Line 3 format is incorrect. Expected 'Regression: <PASS|FAIL>'."
    assert reg_match.group(1) == "PASS", "Regression test did not PASS as expected."

    values = execute_pipeline_and_recompute_results
    recomputed_mean = float(np.mean(values))
    assert lines[0] == f"Overall Mean: {recomputed_mean:.3f}", (
        "Reported overall mean was not computed from simulator runs for seeds 1 through 50"
    )

    assert reported_low <= reported_high, "Bootstrap CI endpoints are reversed"
    assert reported_low <= overall_mean <= reported_high, "Bootstrap CI does not contain the mean"
    assert float(np.min(values)) - 0.001 <= reported_low <= float(np.max(values)) + 0.001
    assert float(np.min(values)) - 0.001 <= reported_high <= float(np.max(values)) + 0.001

    # Estimate the same percentile bootstrap distribution independently with many
    # resamples. A small tolerance permits normal variation from the requested 1000
    # random resamples while rejecting arbitrary fabricated endpoints.
    rng = np.random.default_rng(918273)
    bootstrap_means = rng.choice(values, size=(100000, 50), replace=True).mean(axis=1)
    expected_low, expected_high = np.percentile(bootstrap_means, [2.5, 97.5])
    assert abs(reported_low - expected_low) <= 0.03, (
        f"Reported lower CI endpoint {reported_low} is inconsistent with bootstrapping the 50 means"
    )
    assert abs(reported_high - expected_high) <= 0.03, (
        f"Reported upper CI endpoint {reported_high} is inconsistent with bootstrapping the 50 means"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
