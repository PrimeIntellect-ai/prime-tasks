#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import struct
import subprocess

HOME = "/home/user"
CPP = f"{HOME}/data_prep.cpp"
BINARY = "/tmp/data_prep_submission"
SAMPLES = f"{HOME}/samples.csv"
RESULTS = f"{HOME}/results.txt"
PLOT_SCRIPT = f"{HOME}/plot_samples.py"
IMAGE = f"{HOME}/histogram.png"


def assert_regular_file(path):
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"Expected a regular file: {path}"


def parse_results():
    with open(RESULTS, "r") as f:
        text = f.read()
    exact_match = re.search(r"Exact:\s*([0-9.]+)", text)
    mcmc_match = re.search(r"MCMC:\s*([0-9.]+)", text)
    assert exact_match, "Could not parse 'Exact:' value from results.txt"
    assert mcmc_match, "Could not parse 'MCMC:' value from results.txt"
    return float(exact_match.group(1)), float(mcmc_match.group(1))


def trapezoidal_variance():
    n = 10000
    lo, hi = -10.0, 10.0
    h = (hi - lo) / n
    z = 0.0
    i2 = 0.0
    for i in range(n + 1):
        x = lo + i * h
        fx = math.exp(-x * x / 2.0) * (1.0 + math.sin(2.0 * x) ** 2)
        weight = 0.5 if i == 0 or i == n else 1.0
        z += weight * fx
        i2 += weight * x * x * fx
    return (i2 * h) / (z * h)


def read_samples():
    with open(SAMPLES, "r") as f:
        lines = f.readlines()
    non_empty = [line.strip() for line in lines if line.strip()]
    assert len(non_empty) == 90000, \
        f"Expected 90,000 lines in samples.csv, got {len(non_empty)}"
    values = []
    for lineno, text in enumerate(non_empty, 1):
        try:
            value = float(text)
        except ValueError:
            raise AssertionError(f"Non-numeric sample on line {lineno}: {text!r}")
        assert math.isfinite(value), f"Non-finite sample on line {lineno}"
        values.append(value)
    return values


def test_00_compile_run_and_regenerate_outputs():
    for path in (CPP, PLOT_SCRIPT):
        assert os.path.exists(path), f"Required file missing: {path}"
        assert_regular_file(path)

    subprocess.run(
        ["g++", "-O3", "-std=c++17", CPP, "-o", BINARY],
        check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True
    )

    # Outputs must be produced by the submitted executable, not merely be
    # pre-created files containing self-reported values.
    for path in (SAMPLES, RESULTS):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        [BINARY], check=True, cwd=HOME, timeout=60,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    for path in (SAMPLES, RESULTS):
        assert os.path.exists(path), f"Compiled program did not generate {path}"
        assert_regular_file(path)

    # Run the plotting artifact and observe the bins actually passed through
    # matplotlib's histogram implementation.
    if os.path.lexists(IMAGE):
        os.remove(IMAGE)
    plot_harness = r'''
import runpy
import matplotlib.axes
seen = []
original = matplotlib.axes.Axes.hist

def checked_hist(self, *args, **kwargs):
    result = original(self, *args, **kwargs)
    try:
        seen.append(len(result[1]) - 1)
    except Exception:
        pass
    return result

matplotlib.axes.Axes.hist = checked_hist
runpy.run_path("/home/user/plot_samples.py", run_name="__main__")
if 50 not in seen:
    raise AssertionError("plot_samples.py did not create a 50-bin matplotlib histogram")
'''
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    subprocess.run(
        ["python3", "-c", plot_harness], check=True, cwd=HOME, env=env,
        timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert os.path.exists(IMAGE), "plot_samples.py did not generate histogram.png"
    assert_regular_file(IMAGE)


def test_files_exist():
    """Verify that all required files exist."""
    expected_files = [CPP, SAMPLES, RESULTS, PLOT_SCRIPT, IMAGE]
    for filepath in expected_files:
        assert os.path.exists(filepath), f"Required file missing: {filepath}"


def test_results_txt_content():
    """Verify the contents and calculated variances in results.txt."""
    exact_val, mcmc_val = parse_results()
    assert 1.000 <= exact_val <= 1.004, \
        f"Exact variance {exact_val} is outside expected bounds [1.000, 1.004]"
    assert 0.95 <= mcmc_val <= 1.05, \
        f"MCMC variance {mcmc_val} is outside expected bounds [0.95, 1.05]"

    expected_exact = trapezoidal_variance()
    assert abs(exact_val - expected_exact) <= 2e-5, \
        f"Reported exact variance {exact_val} does not match N=10000 trapezoidal integration ({expected_exact})"


def test_samples_csv_length():
    """Verify that samples.csv contains exactly 90,000 numeric lines."""
    read_samples()


def test_samples_and_reported_variance_are_consistent_with_target_mcmc():
    values = read_samples()
    n = len(values)
    mean = sum(values) / n
    variance = sum((x - mean) ** 2 for x in values) / n
    fourth = sum(x ** 4 for x in values) / n
    cosine_moment = sum(math.cos(4.0 * x) for x in values) / n
    rejection_fraction = sum(
        1 for a, b in zip(values, values[1:]) if a == b
    ) / (n - 1)

    _, reported_mcmc = parse_results()
    assert abs(reported_mcmc - variance) <= 2e-5, \
        f"Reported MCMC variance {reported_mcmc} does not match samples.csv variance {variance}"
    assert abs(mean) <= 0.06, f"Sample mean {mean} is inconsistent with the symmetric target"
    assert 2.5 <= fourth <= 3.5, f"Sample fourth moment {fourth} is inconsistent with the target"
    assert -0.23 <= cosine_moment <= -0.10, \
        f"Samples do not reflect the sinusoidal factor in the target density (cos(4x) moment={cosine_moment})"
    assert 0.10 <= rejection_fraction <= 0.50, \
        f"Consecutive-state rejection rate {rejection_fraction} is inconsistent with the requested Metropolis-Hastings chain"


def test_histogram_png_valid():
    """Verify that histogram.png is generated, nonempty, and is a real PNG."""
    assert os.path.getsize(IMAGE) > 0, "histogram.png exists but is empty"
    with open(IMAGE, "rb") as f:
        header = f.read(24)
    assert len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n", \
        "histogram.png is not a valid PNG file"
    assert header[12:16] == b"IHDR", "histogram.png lacks a PNG IHDR chunk"
    width, height = struct.unpack(">II", header[16:24])
    assert width > 0 and height > 0, "histogram.png has invalid dimensions"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
