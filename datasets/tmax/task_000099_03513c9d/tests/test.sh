#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:$PATH"
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess
import tempfile

import numpy as np
import pytest

PROJECT = "/home/user/analyzer"
REPORT = "/home/user/report.json"
REF_DIR = "/home/user/data/reference"
SIM_DIR = "/home/user/data/simulation"


def run_analyzer():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert result.returncode == 0, f"The Rust analyzer failed to build or run:\n{result.stdout}"
    assert os.path.isfile(REPORT), f"The report file {REPORT} was not created by the analyzer."


def load_report():
    with open(REPORT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT} does not contain valid JSON.")


def peak_frequencies(directory, prefix):
    peaks = []
    for i in range(100):
        path = os.path.join(directory, f"{prefix}_{i}.csv")
        assert os.path.isfile(path), f"Missing input CSV: {path}"
        values = np.genfromtxt(path, delimiter=",", skip_header=1, usecols=1)
        assert values.shape == (1000,), f"Unexpected sample count in {path}"
        magnitudes = np.abs(np.fft.rfft(values))
        peaks.append(float(np.argmax(magnitudes)))  # 1000 samples at 1000 Hz => 1 Hz/bin
    return np.asarray(peaks, dtype=np.float64)


def expected_statistics(ref_peaks, sim_peaks):
    # This independently derives expected percentile-bootstrap answers. The exact
    # ChaCha stream can move an empirical endpoint slightly, so comparisons use
    # the instruction's stated 0.5 tolerance.
    rng = np.random.default_rng(42)
    result = []
    for peaks in (ref_peaks, sim_peaks):
        indices = rng.integers(0, len(peaks), size=(10000, len(peaks)))
        bootstrap_means = peaks[indices].mean(axis=1)
        lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])
        result.append((float(peaks.mean()), float(lower), float(upper)))
    return result


def assert_matches_expected(data, expected, tolerance=0.5):
    for name, values in zip(("reference", "simulation"), expected):
        for key, target in zip(("mean_peak_freq", "ci_lower", "ci_upper"), values):
            actual = data[name][key]
            assert math.isfinite(actual), f"{name}.{key} must be finite."
            assert abs(actual - target) <= tolerance, (
                f"{name}.{key} was {actual}, but the value derived from the CSV data "
                f"is {target} (tolerance {tolerance})."
            )


@pytest.fixture(scope="module", autouse=True)
def execute_submission():
    assert os.path.isdir(PROJECT), "The required /home/user/analyzer project is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    src_dir = os.path.join(PROJECT, "src")
    assert os.path.isdir(src_dir), "The Rust project's src directory is missing."
    assert any(name.endswith(".rs") for _, _, files in os.walk(src_dir) for name in files), \
        "The project contains no Rust source files."
    run_analyzer()


def test_report_exists():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."


def test_report_content_and_logic():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Cannot test content because {report_path} does not exist."

    data = load_report()

    assert "reference" in data, "The JSON report is missing the 'reference' key."
    assert "simulation" in data, "The JSON report is missing the 'simulation' key."

    ref = data["reference"]
    sim = data["simulation"]

    expected_keys = ["mean_peak_freq", "ci_lower", "ci_upper"]
    for key in expected_keys:
        assert key in ref, f"The 'reference' object is missing the '{key}' key."
        assert key in sim, f"The 'simulation' object is missing the '{key}' key."
        assert isinstance(ref[key], (int, float)), f"reference.{key} must be a number."
        assert isinstance(sim[key], (int, float)), f"simulation.{key} must be a number."

    ref_mean = ref["mean_peak_freq"]
    sim_mean = sim["mean_peak_freq"]

    assert 48.0 < ref_mean < 52.0, f"Reference mean_peak_freq ({ref_mean}) is out of expected bounds (48.0 - 52.0)."
    assert 75.0 < sim_mean < 85.0, f"Simulation mean_peak_freq ({sim_mean}) is out of expected bounds (75.0 - 85.0)."

    assert ref["ci_lower"] < ref_mean < ref["ci_upper"], \
        f"Reference confidence interval is invalid: {ref['ci_lower']} < {ref_mean} < {ref['ci_upper']} is False."
    assert sim["ci_lower"] < sim_mean < sim["ci_upper"], \
        f"Simulation confidence interval is invalid: {sim['ci_lower']} < {sim_mean} < {sim['ci_upper']} is False."

    expected = expected_statistics(
        peak_frequencies(REF_DIR, "ref"),
        peak_frequencies(SIM_DIR, "sim"),
    )
    assert_matches_expected(data, expected)


def write_synthetic_dataset(directory, prefix, frequencies):
    os.makedirs(directory)
    for i, frequency in enumerate(frequencies):
        path = os.path.join(directory, f"{prefix}_{i}.csv")
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["time", "amplitude"])
            for sample in range(1000):
                t = sample / 1000.0
                writer.writerow([t, math.sin(2.0 * math.pi * frequency * t)])


def test_analyzer_reacts_to_csv_contents_and_computes_statistics():
    # Replace the inputs temporarily with hidden, exactly analyzable signals. This
    # rejects a prewritten or hard-coded report and exercises the built Rust binary.
    temp_root = tempfile.mkdtemp(prefix="analyzer-verifier-")
    saved_ref = os.path.join(temp_root, "reference")
    saved_sim = os.path.join(temp_root, "simulation")
    saved_report = None
    if os.path.isfile(REPORT):
        with open(REPORT, "rb") as f:
            saved_report = f.read()

    os.rename(REF_DIR, saved_ref)
    os.rename(SIM_DIR, saved_sim)
    try:
        ref_frequencies = [20 + (i % 10) for i in range(100)]
        sim_frequencies = [180 + (i % 20) for i in range(100)]
        write_synthetic_dataset(REF_DIR, "ref", ref_frequencies)
        write_synthetic_dataset(SIM_DIR, "sim", sim_frequencies)

        expected = expected_statistics(
            np.asarray(ref_frequencies, dtype=np.float64),
            np.asarray(sim_frequencies, dtype=np.float64),
        )
        run_analyzer()
        data = load_report()
        assert isinstance(data, dict)
        assert "reference" in data and "simulation" in data
        for section in ("reference", "simulation"):
            for key in ("mean_peak_freq", "ci_lower", "ci_upper"):
                assert key in data[section]
                assert isinstance(data[section][key], (int, float))
        assert_matches_expected(data, expected)
    finally:
        if os.path.isdir(REF_DIR):
            shutil.rmtree(REF_DIR)
        if os.path.isdir(SIM_DIR):
            shutil.rmtree(SIM_DIR)
        os.rename(saved_ref, REF_DIR)
        os.rename(saved_sim, SIM_DIR)
        if saved_report is not None:
            with open(REPORT, "wb") as f:
                f.write(saved_report)
        elif os.path.exists(REPORT):
            os.remove(REPORT)
        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
