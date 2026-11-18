#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import tempfile

import numpy as np
import pytest

SIM_SOURCE = r'''#include <iostream>
#include <vector>
#include <chrono>
#include <cmath>
#include <iomanip>

int main() {
    auto start = std::chrono::high_resolution_clock::now();

    double sum = 0.0;
    // Simulate some scientific workload
    for (int i = 0; i < 5000; ++i) {
        for (int j = 0; j < 5000; ++j) {
            sum += std::sin(i) * std::cos(j);
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = end - start;

    // Output state
    std::cout << "State: " << std::fixed << std::setprecision(5) << sum << std::endl;
    std::cout << "Time: " << duration.count() << " ms" << std::endl;

    return 0;
}
'''
TIME_RE = re.compile(r"Time:\s*([0-9]+(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)\s+ms")


def test_executables_exist():
    assert os.path.isfile("/home/user/sim_o2"), "/home/user/sim_o2 executable is missing."
    assert os.access("/home/user/sim_o2", os.X_OK), "/home/user/sim_o2 is not executable."
    assert os.path.isfile("/home/user/sim_o3"), "/home/user/sim_o3 executable is missing."
    assert os.access("/home/user/sim_o3", os.X_OK), "/home/user/sim_o3 is not executable."


def test_profile_report_exists():
    assert os.path.isfile("/home/user/profile_report.json"), "/home/user/profile_report.json is missing."


def compile_reference_and_compare_sections(submitted, flags, workdir, stem):
    source = os.path.join(workdir, "reference_sim.cpp")
    reference = os.path.join(workdir, stem)
    with open(source, "w", encoding="utf-8") as f:
        f.write(SIM_SOURCE)
    proc = subprocess.run(
        ["g++", *flags, source, "-o", reference],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.returncode == 0, f"Could not compile verifier reference: {proc.stderr}"

    # Compare the generated program and constants while allowing harmless differences
    # in ELF metadata, symbols, or stripping.
    for section in (".text", ".rodata"):
        actual_dump = os.path.join(workdir, stem + ".actual" + section)
        reference_dump = os.path.join(workdir, stem + ".reference" + section)
        for binary, output in ((submitted, actual_dump), (reference, reference_dump)):
            result = subprocess.run(
                ["objcopy", f"--dump-section", f"{section}={output}", binary],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert result.returncode == 0 and os.path.isfile(output), (
                f"{binary} is not a valid compiled executable with section {section}: "
                f"{result.stderr}"
            )
        with open(actual_dump, "rb") as f:
            actual_bytes = f.read()
        with open(reference_dump, "rb") as f:
            reference_bytes = f.read()
        assert actual_bytes == reference_bytes, (
            f"{submitted} does not match sim.cpp compiled with {' '.join(flags)}"
        )


def run_simulation(path):
    result = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"{path} failed: {result.stderr}"
    lines = result.stdout.splitlines()
    assert len(lines) >= 2, f"{path} did not print a state line followed by a timing line"
    match = TIME_RE.fullmatch(lines[1].strip())
    assert match is not None, f"Invalid timing line from {path}: {lines[1]!r}"
    elapsed = float(match.group(1))
    assert math.isfinite(elapsed) and elapsed >= 0.0, f"Invalid execution time from {path}"
    return lines[0], elapsed


@pytest.fixture(scope="session")
def measured_results():
    test_executables_exist()
    with tempfile.TemporaryDirectory() as workdir:
        compile_reference_and_compare_sections(
            "/home/user/sim_o2", ["-O2"], workdir, "reference_o2"
        )
        compile_reference_and_compare_sections(
            "/home/user/sim_o3", ["-O3", "-ffast-math"], workdir, "reference_o3"
        )

    o2_times = []
    o3_times = []
    expected_state = None
    # Alternate binaries to reduce bias from machine load while obtaining exactly
    # 50 independent executions of each submitted executable.
    for _ in range(50):
        o2_state, o2_time = run_simulation("/home/user/sim_o2")
        o3_state, o3_time = run_simulation("/home/user/sim_o3")
        assert o2_state == o3_state, "O2 and O3 first output lines are not strictly identical"
        if expected_state is None:
            expected_state = o2_state
        assert o2_state == expected_state and o3_state == expected_state, (
            "The simulation state changed between profiling runs"
        )
        o2_times.append(o2_time)
        o3_times.append(o3_time)

    # Independently recompute the requested percentile bootstrap using exactly
    # 10,000 resamples and seed 42.
    o2 = np.asarray(o2_times, dtype=float)
    o3 = np.asarray(o3_times, dtype=float)
    rng = np.random.RandomState(42)
    differences = np.empty(10000, dtype=float)
    for i in range(10000):
        differences[i] = (
            o2[rng.randint(0, 50, size=50)].mean()
            - o3[rng.randint(0, 50, size=50)].mean()
        )
    lower, upper = np.percentile(differences, [2.5, 97.5])
    return {
        "mean_diff": float(o2.mean() - o3.mean()),
        "ci_lower": float(lower),
        "ci_upper": float(upper),
        "scale": float(max(o2.mean(), o3.mean(), 1.0)),
        "standard_error": float(
            math.sqrt(np.var(o2, ddof=1) / 50.0 + np.var(o3, ddof=1) / 50.0)
        ),
    }


def test_profile_report_content(measured_results):
    report_path = "/home/user/profile_report.json"
    assert os.path.isfile(report_path), f"{report_path} does not exist."
    with open(report_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {report_path} is not valid JSON: {exc}")

    assert "regression_passed" in data, "Missing 'regression_passed' in report."
    assert "mean_diff" in data, "Missing 'mean_diff' in report."
    assert "ci_lower" in data, "Missing 'ci_lower' in report."
    assert "ci_upper" in data, "Missing 'ci_upper' in report."
    assert set(data) == {"regression_passed", "mean_diff", "ci_lower", "ci_upper"}, (
        "The report must contain exactly the four requested keys."
    )
    assert data["regression_passed"] is True, "'regression_passed' must be true."
    assert isinstance(data["mean_diff"], (float, int)) and not isinstance(data["mean_diff"], bool)
    assert isinstance(data["ci_lower"], (float, int)) and not isinstance(data["ci_lower"], bool)
    assert isinstance(data["ci_upper"], (float, int)) and not isinstance(data["ci_upper"], bool)

    reported_mean = float(data["mean_diff"])
    reported_lower = float(data["ci_lower"])
    reported_upper = float(data["ci_upper"])
    assert all(math.isfinite(x) for x in (reported_mean, reported_lower, reported_upper))
    assert reported_lower < reported_upper, "'ci_lower' must be strictly less than 'ci_upper'."
    assert reported_lower <= reported_mean <= reported_upper, (
        "The reported percentile interval must contain the reported mean difference."
    )

    fresh_mean = measured_results["mean_diff"]
    fresh_lower = measured_results["ci_lower"]
    fresh_upper = measured_results["ci_upper"]
    scale = measured_results["scale"]
    se = measured_results["standard_error"]
    fresh_width = fresh_upper - fresh_lower
    reported_width = reported_upper - reported_lower

    # Timings from two genuine 50-run profiles will not be bit-identical, so use
    # tolerances tied to runtime and observed sampling noise while rejecting a
    # fabricated report unrelated to the measured binaries.
    mean_tolerance = max(0.10 * scale, 4.0 * se, 1e-6)
    endpoint_tolerance = max(0.15 * scale, 4.0 * fresh_width, 1e-6)
    assert abs(reported_mean - fresh_mean) <= mean_tolerance, (
        f"Reported mean difference {reported_mean} is inconsistent with a fresh "
        f"50-run profile ({fresh_mean})."
    )
    assert abs(reported_lower - fresh_lower) <= endpoint_tolerance, (
        "Reported lower bootstrap endpoint is inconsistent with the measured samples."
    )
    assert abs(reported_upper - fresh_upper) <= endpoint_tolerance, (
        "Reported upper bootstrap endpoint is inconsistent with the measured samples."
    )
    if fresh_width > 1e-9:
        ratio = reported_width / fresh_width
        assert 0.05 <= ratio <= 20.0, (
            "Reported confidence-interval width is incompatible with a 10,000-resample bootstrap."
        )
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
