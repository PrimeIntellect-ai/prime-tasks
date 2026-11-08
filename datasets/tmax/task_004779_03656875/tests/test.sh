#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import re
import secrets
import stat
import struct
import subprocess

import numpy as np
from scipy.integrate import cumulative_trapezoid
from scipy.optimize import curve_fit

HOME = "/home/user"
INPUT = f"{HOME}/reaction_rate.csv"
WORKFLOW = f"{HOME}/run_workflow.sh"
ANALYZE = f"{HOME}/analyze.py"
PLOT = f"{HOME}/plot.gnu"
PARAMS = f"{HOME}/fit_params.txt"
DATA = f"{HOME}/integrated_data.csv"
PNG = f"{HOME}/result_plot.png"


def assert_regular_file(path):
    assert os.path.exists(path), f"{path} does not exist."
    assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"{path} is not a regular file."
    assert os.path.getsize(path) > 0, f"{path} is empty."


def write_input(times, rates):
    with open(INPUT, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Time", "Rate"])
        writer.writerows(zip(times, rates))


def baseline_input():
    true_A = 5.0
    true_k = 0.2
    times = np.linspace(0, 20, 100)
    rng = np.random.RandomState(42)
    rates = true_A * true_k * np.exp(-true_k * times)
    rates = rates + rng.normal(0, 0.001, size=times.shape)
    return times, rates


def run_workflow():
    for path in (PARAMS, DATA, PNG):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        [WORKFLOW], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=60
    )
    assert result.returncode == 0, f"Workflow failed:\n{result.stdout}"


def parse_params(strict=False):
    assert_regular_file(PARAMS)
    with open(PARAMS) as f:
        content = f.read().strip()
    match = re.search(r"A=([0-9.]+),\s*k=([0-9.]+)", content)
    assert match is not None, f"Could not parse A and k from {PARAMS}. Content was: {content}"
    if strict:
        assert re.fullmatch(r"A=[0-9]+\.[0-9]{3}, k=[0-9]+\.[0-9]{3}", content), \
            f"Incorrect fit parameter format: {content!r}"
    return float(match.group(1)), float(match.group(2))


def read_integrated():
    assert_regular_file(DATA)
    with open(DATA, newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)
    assert rows, f"{DATA} is empty."
    header = ",".join(rows[0])
    assert header == "Time,Cumulative_C,Fitted_C", f"Incorrect header in {DATA}. Got: {header}"
    assert len(rows) > 1, f"{DATA} contains no data rows."
    assert all(len(row) == 3 for row in rows[1:]), "Every integrated-data row must have three columns."
    try:
        values = np.asarray([[float(x) for x in row] for row in rows[1:]], dtype=float)
    except ValueError as exc:
        raise AssertionError(f"Non-numeric value in {DATA}: {exc}")
    assert np.all(np.isfinite(values)), f"{DATA} contains non-finite values."
    return values


def validate_png(path=PNG):
    assert_regular_file(path)
    with open(path, "rb") as f:
        blob = f.read()
    assert blob[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a valid PNG file."
    assert len(blob) > 2000, f"{path} is implausibly small for the requested graph."
    assert blob[12:16] == b"IHDR" and len(blob) >= 33, f"{path} has no valid IHDR chunk."
    width, height = struct.unpack(">II", blob[16:24])
    assert width >= 300 and height >= 200, f"Plot dimensions are too small: {width}x{height}."
    assert b"IDAT" in blob and blob.endswith(b"IEND\xaeB`\x82"), f"{path} is an incomplete PNG."
    return hashlib.sha256(blob).hexdigest()


def reference_fit(times, rates):
    cumulative = cumulative_trapezoid(rates, times, initial=0.0)

    def model(t, A, k):
        return A * (1.0 - np.exp(-k * t))

    params, _ = curve_fit(
        model, times, cumulative,
        p0=(max(float(cumulative[-1]), 0.1), 0.2),
        bounds=(0, np.inf), maxfev=20000
    )
    return cumulative, params, model(times, *params)


def verify_numerical_outputs(times, rates):
    expected_c, expected_params, expected_fit = reference_fit(times, rates)
    actual = read_integrated()
    assert actual.shape == (len(times), 3), \
        f"Expected {len(times)} data rows and three columns, got {actual.shape}."
    assert np.allclose(actual[:, 0], times, rtol=0, atol=1e-10), "Time column does not match the input."
    assert np.allclose(actual[:, 1], expected_c, rtol=1e-8, atol=1e-8), \
        "Cumulative_C is not the cumulative trapezoidal integral of Rate."
    assert np.allclose(actual[:, 2], expected_fit, rtol=2e-5, atol=2e-5), \
        "Fitted_C does not contain predictions from the fitted first-order model."
    A, k = parse_params(strict=True)
    assert f"{A:.3f}" == f"{expected_params[0]:.3f}", "Reported A is not the fitted value."
    assert f"{k:.3f}" == f"{expected_params[1]:.3f}", "Reported k is not the fitted value."


def render_current_plot():
    result = subprocess.run(
        ["gnuplot", PLOT], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=30
    )
    assert result.returncode == 0, f"Gnuplot script failed:\n{result.stdout}"
    return validate_png()


def write_plot_probe(second_variant=0, third_variant=0):
    x = np.linspace(0, 10, 31)
    second = 1.0 + 0.08 * x
    third = 1.8 - 0.05 * x
    if second_variant:
        second = 0.5 + 1.2 * np.sin(x * 1.7) ** 2
    if third_variant:
        third = 0.4 + 0.12 * x + 0.8 * np.cos(x * 1.3) ** 2
    with open(DATA, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Time", "Cumulative_C", "Fitted_C"])
        writer.writerows(zip(x, second, third))


def test_complete_workflow():
    for path in (ANALYZE, PLOT, WORKFLOW):
        assert_regular_file(path)
    assert os.access(WORKFLOW, os.X_OK), f"{WORKFLOW} is not executable."

    # Retain the original checks on the image's intended data, but obtain all
    # artifacts by actually executing the submitted orchestration script.
    base_t, base_r = baseline_input()
    write_input(base_t, base_r)
    run_workflow()
    A, k = parse_params()
    assert 4.8 <= A <= 5.2, f"Value of A ({A}) is too far from expected 5.0"
    assert 0.15 <= k <= 0.25, f"Value of k ({k}) is too far from expected 0.2"
    verify_numerical_outputs(base_t, base_r)
    validate_png()

    # Exercise the implementation on a verifier-generated case so fixed
    # parameters or precomputed output cannot pass.
    rng = np.random.default_rng(secrets.randbits(128))
    true_A = float(rng.uniform(2.2, 8.0))
    true_k = float(rng.uniform(0.075, 0.42))
    count = int(rng.integers(67, 119))
    end = float(rng.uniform(14.0, 30.0))
    times = np.linspace(0.0, end, count)
    rates = true_A * true_k * np.exp(-true_k * times)
    rates += rng.normal(0.0, true_A * true_k * 0.00035, size=count)
    write_input(times, rates)
    run_workflow()
    verify_numerical_outputs(times, rates)
    validate_png()

    # Confirm that plot.gnu really consumes and plots each requested data
    # column, rather than merely creating a file with PNG magic bytes.
    write_plot_probe()
    plot_1 = render_current_plot()
    plot_1_repeat = render_current_plot()
    assert plot_1 == plot_1_repeat, "Repeated rendering of identical plot data is not deterministic."
    write_plot_probe(second_variant=1)
    plot_2 = render_current_plot()
    assert plot_2 != plot_1, "Changing Cumulative_C did not affect the generated plot."
    write_plot_probe(third_variant=1)
    plot_3 = render_current_plot()
    assert plot_3 != plot_1, "Changing Fitted_C did not affect the generated plot."

    # Leave the requested outputs corresponding to the original input.
    write_input(base_t, base_r)
    run_workflow()
    verify_numerical_outputs(base_t, base_r)
    validate_png()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
