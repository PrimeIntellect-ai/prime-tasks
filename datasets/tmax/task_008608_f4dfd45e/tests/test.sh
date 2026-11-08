#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

import numpy as np
import pytest
from scipy.optimize import differential_evolution, least_squares, nnls
from scipy.stats import f as f_distribution

SIMULATOR_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double randn(double mu, double sigma) {
    double U1, U2, W, mult;
    static double X1, X2;
    static int call = 0;
    if (call == 1) {
        call = !call;
        return (mu + sigma * (double) X2);
    }
    do {
        U1 = -1 + ((double) rand() / RAND_MAX) * 2;
        U2 = -1 + ((double) rand() / RAND_MAX) * 2;
        W = pow(U1, 2) + pow(U2, 2);
    } while (W >= 1 || W == 0);
    mult = sqrt((-2 * log(W)) / W);
    X1 = U1 * mult;
    X2 = U2 * mult;
    call = !call;
    return (mu + sigma * (double) X1);
}

int main() {
    srand(42);
    int N = 100;
    double t_max = 10.0;
    printf("t,y\n");
    for (int i = 0; i < N; i++) {
        double t = i * (t_max / (N - 1));
        double y_true = 5.0 * exp(-1.5 * t) + 2.0 * exp(-0.2 * t);
        double y_noisy = y_true + randn(0.0, 0.1);
        printf("%.4f,%.4f\n", t, y_noisy);
    }
    return 0;
}
'''


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, timeout=120, **kwargs)


def reference_simulator_output():
    with tempfile.TemporaryDirectory() as directory:
        source_path = os.path.join(directory, "simulate_decay.c")
        executable_path = os.path.join(directory, "simulate_decay")
        with open(source_path, "w") as source_file:
            source_file.write(SIMULATOR_SOURCE)
        run_checked(["gcc", source_path, "-o", executable_path, "-lm"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return run_checked([executable_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def test_executable_exists():
    executable_path = "/home/user/simulate_decay"
    assert os.path.exists(executable_path), f"The executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."
    assert os.path.isfile(executable_path), f"The executable {executable_path} is not a regular file."
    with open(executable_path, "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", "simulate_decay must be a compiled ELF executable."


def test_data_csv_exists_and_format():
    data_path = "/home/user/data.csv"
    assert os.path.exists(data_path), f"The data file {data_path} is missing."

    with open(data_path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 101, f"Expected 101 lines in data.csv (header + 100 data points), but found {len(lines)}."
    assert lines[0].strip() == "t,y", "The header of data.csv should be 't,y'."

    for i, line in enumerate(lines[1:], start=1):
        parts = line.split(",")
        assert len(parts) == 2, f"Line {i+1} does not have exactly two columns: {line}"
        try:
            float(parts[0])
            float(parts[1])
        except ValueError:
            pytest.fail(f"Line {i+1} contains non-numeric data: {line}")

    submitted_output = run_checked(
        ["/home/user/simulate_decay"], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    expected_output = reference_simulator_output()
    with open(data_path, "rb") as data_file:
        saved_output = data_file.read()

    assert submitted_output == expected_output, "simulate_decay output does not match the supplied deterministic simulator."
    assert saved_output == submitted_output, "data.csv was not generated from the submitted simulate_decay executable."


def test_analysis_script_executes_and_generates_results():
    script_path = "/home/user/analyze.py"
    result_path = "/home/user/stats_result.txt"
    assert os.path.exists(script_path), f"The analysis script {script_path} is missing."
    assert os.path.isfile(script_path), f"The analysis script {script_path} is not a regular file."
    if os.path.exists(result_path):
        os.remove(result_path)
    run_checked(
        ["python3", script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert os.path.exists(result_path), "analyze.py did not generate stats_result.txt."


def independently_fit_models(t, y):
    def null_residual(parameters):
        amplitude, rate = parameters
        return amplitude * np.exp(-rate * t) - y

    null_fit = least_squares(
        null_residual,
        x0=np.array([max(float(np.max(y)), 1.0), 0.5]),
        bounds=(0.0, np.inf),
        xtol=1e-14,
        ftol=1e-14,
        gtol=1e-14,
        max_nfev=20000,
    )
    rss0 = float(np.dot(null_fit.fun, null_fit.fun))

    def profiled_rss(rates):
        design = np.column_stack((np.exp(-rates[0] * t), np.exp(-rates[1] * t)))
        amplitudes, _ = nnls(design, y)
        residual = design @ amplitudes - y
        return float(np.dot(residual, residual))

    global_rates = differential_evolution(
        profiled_rss,
        bounds=[(0.0, 10.0), (0.0, 10.0)],
        seed=731,
        popsize=20,
        maxiter=400,
        tol=1e-11,
        polish=True,
        updating="immediate",
    ).x
    design = np.column_stack((np.exp(-global_rates[0] * t), np.exp(-global_rates[1] * t)))
    amplitudes, _ = nnls(design, y)

    def alternative_residual(parameters):
        amplitude_a, rate_a, amplitude_b, rate_b = parameters
        return amplitude_a * np.exp(-rate_a * t) + amplitude_b * np.exp(-rate_b * t) - y

    alternative_fit = least_squares(
        alternative_residual,
        x0=np.array([amplitudes[0], global_rates[0], amplitudes[1], global_rates[1]]),
        bounds=(0.0, np.inf),
        xtol=1e-14,
        ftol=1e-14,
        gtol=1e-14,
        max_nfev=50000,
    )
    rss1 = float(np.dot(alternative_fit.fun, alternative_fit.fun))
    f_stat = ((rss0 - rss1) / 2.0) / (rss1 / 96.0)
    p_value = float(f_distribution.sf(f_stat, 2, 96))
    return rss0, rss1, f_stat, p_value


def test_stats_result():
    result_path = "/home/user/stats_result.txt"
    assert os.path.exists(result_path), f"The results file {result_path} is missing."

    with open(result_path, "r") as f:
        content = f.read().strip()

    lines = content.split("\n")
    assert len(lines) == 4, f"Expected exactly 4 lines in stats_result.txt, found {len(lines)}."

    patterns = [
        r"^Model 0 RSS:\s*([0-9.]+)$",
        r"^Model 1 RSS:\s*([0-9.]+)$",
        r"^F-statistic:\s*([0-9.]+)$",
        r"^p-value:\s*([0-9.]+)$"
    ]
    exact_patterns = [
        r"^Model 0 RSS:\s*[0-9]+\.[0-9]{4}$",
        r"^Model 1 RSS:\s*[0-9]+\.[0-9]{4}$",
        r"^F-statistic:\s*[0-9]+\.[0-9]{4}$",
        r"^p-value:\s*[0-9]+\.[0-9]{4}$"
    ]

    values = []
    for i, (line, pattern) in enumerate(zip(lines, patterns)):
        match = re.match(pattern, line.strip())
        assert match, f"Line {i+1} does not match the required format. Got: '{line}'"
        assert re.match(exact_patterns[i], line.strip()), f"Line {i+1} must contain a value rounded to exactly 4 decimal places."
        values.append(float(match.group(1)))

    rss0, rss1, f_stat, p_val = values

    assert 0.5 < rss1 < 3.0, f"Model 1 RSS ({rss1}) is outside the expected range for a good fit."
    assert 10.0 < rss0 < 40.0, f"Model 0 RSS ({rss0}) is outside the expected range."
    assert rss1 < rss0, "Model 1 RSS should be lower than Model 0 RSS."

    expected_f_stat = ((rss0 - rss1) / 2.0) / (rss1 / 96.0)
    f_stat_diff = abs(f_stat - expected_f_stat)
    assert f_stat_diff / expected_f_stat < 0.05, \
        f"Reported F-statistic {f_stat} does not match the expected value {expected_f_stat:.4f} computed from the reported RSS values."
    assert 0.0 <= p_val < 0.01, f"Expected a very small p-value, but got {p_val}."

    data = np.genfromtxt("/home/user/data.csv", delimiter=",", names=True)
    assert len(data) == 100
    reference_values = independently_fit_models(
        np.asarray(data["t"], dtype=float), np.asarray(data["y"], dtype=float)
    )
    labels = ["Model 0 RSS", "Model 1 RSS", "F-statistic", "p-value"]
    for label, reported, reference in zip(labels, values, reference_values):
        rounded_reference = float(f"{reference:.4f}")
        assert math.isclose(reported, rounded_reference, rel_tol=0.0, abs_tol=0.00011), \
            f"Reported {label} {reported:.4f} does not match the independently computed value {rounded_reference:.4f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
