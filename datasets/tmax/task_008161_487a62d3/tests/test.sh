#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

SOURCE_PATH = "/home/user/analyzer.cpp"
TRACE_PATH = "/home/user/perf_trace.txt"
REPORT_PATH = "/home/user/report.txt"
SPECTRUM_PATH = "/home/user/spectrum.csv"
SUBMISSION_BIN = "/tmp/verifier_analyzer"
ORACLE_SOURCE = "/tmp/verifier_oracle.cpp"
ORACLE_BIN = "/tmp/verifier_oracle"

ORACLE_CODE = r'''
#include <algorithm>
#include <cmath>
#include <complex>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <string>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    std::ifstream in(argv[1]);
    std::vector<double> x;
    double value;
    while (in >> value) x.push_back(value);
    if (x.size() != 1024) return 3;

    const int n = 1024;
    const double pi = std::acos(-1.0);
    std::vector<double> magnitude(512);
    for (int k = 0; k < 512; ++k) {
        std::complex<double> sum(0.0, 0.0);
        for (int t = 0; t < n; ++t) {
            double angle = -2.0 * pi * k * t / n;
            sum += x[t] * std::complex<double>(std::cos(angle), std::sin(angle));
        }
        magnitude[k] = std::abs(sum);
    }

    int dominant = 1;
    for (int k = 2; k < 512; ++k) {
        if (magnitude[k] > magnitude[dominant]) dominant = k;
    }

    std::mt19937 gen(42);
    std::uniform_int_distribution<> dis(0, 1023);
    std::vector<double> means(10000);
    for (int r = 0; r < 10000; ++r) {
        double sum = 0.0;
        for (int j = 0; j < 1024; ++j) sum += x[dis(gen)];
        means[r] = sum / 1024.0;
    }
    std::sort(means.begin(), means.end());

    std::ofstream report(argv[2]);
    if (!report) return 4;
    report << "Dominant Frequency Bin: " << dominant << "\n";
    report << std::fixed << std::setprecision(3)
           << "Mean 95% CI: [" << means[250] << ", " << means[9749] << "]\n";

    std::ofstream spectrum(argv[3]);
    if (!spectrum) return 5;
    spectrum << std::setprecision(17);
    for (int k = 0; k < 512; ++k) spectrum << k << ',' << magnitude[k] << '\n';
    return 0;
}
'''

REPORT_RE = re.compile(
    r"Dominant Frequency Bin: (\d+)\n"
    r"Mean 95% CI: \[([-+]?\d+\.\d{3}), ([-+]?\d+\.\d{3})\]\n?"
)


def compile_programs():
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."
    assert os.path.getsize(SOURCE_PATH) > 0, f"{SOURCE_PATH} is empty."

    submitted = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_PATH, "-o", SUBMISSION_BIN],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert submitted.returncode == 0, "analyzer.cpp did not compile:\n" + submitted.stderr

    with open(ORACLE_SOURCE, "w") as f:
        f.write(ORACLE_CODE)
    oracle = subprocess.run(
        ["g++", "-O3", "-std=c++17", ORACLE_SOURCE, "-o", ORACLE_BIN],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert oracle.returncode == 0, "Internal oracle compilation failed:\n" + oracle.stderr


def parse_report(path):
    assert os.path.exists(path), f"{path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    with open(path, "r") as f:
        content = f.read()
    match = REPORT_RE.fullmatch(content)
    assert match is not None, "Mean 95% CI format is incorrect or report.txt is not in the exact required format."
    return int(match.group(1)), match.group(2), match.group(3), content


def parse_spectrum(path):
    assert os.path.exists(path), f"{path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    with open(path, "r") as f:
        lines = f.readlines()

    assert len(lines) >= 512, f"{path} does not contain enough bins (expected at least 512 lines)."
    rows = []
    for line in lines:
        parts = line.strip().split(',')
        if len(parts) != 2:
            continue
        try:
            bin_value = float(parts[0])
            magnitude = float(parts[1])
        except ValueError:
            continue
        assert math.isfinite(bin_value) and math.isfinite(magnitude), "Spectrum contains a non-finite number."
        rows.append((bin_value, magnitude))

    assert len(rows) >= 512, f"{path} does not contain at least 512 valid 'bin,magnitude' lines."
    assert len(rows) == 512, "spectrum.csv must contain exactly one numeric row for each bin 0 through 511."
    for expected_bin, (actual_bin, _) in enumerate(rows):
        assert actual_bin == expected_bin, f"Expected spectrum bin {expected_bin}, got {actual_bin}."
    return rows


def run_and_check(original_case=False):
    for path in (REPORT_PATH, SPECTRUM_PATH):
        if os.path.lexists(path):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)
            else:
                pytest.fail(f"{path} is not a regular output file")

    run = subprocess.run(
        [SUBMISSION_BIN], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert run.returncode == 0, "Compiled analyzer failed when executed:\n" + run.stderr

    with tempfile.TemporaryDirectory() as td:
        expected_report = os.path.join(td, "report.txt")
        expected_spectrum = os.path.join(td, "spectrum.csv")
        oracle = subprocess.run(
            [ORACLE_BIN, TRACE_PATH, expected_report, expected_spectrum],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        assert oracle.returncode == 0, "Internal expected-result computation failed."

        actual_dom, actual_low, actual_high, content = parse_report(REPORT_PATH)
        expected_dom, expected_low, expected_high, _ = parse_report(expected_report)

        assert actual_dom == expected_dom, f"Incorrect dominant frequency bin: expected {expected_dom}, got {actual_dom}."
        assert actual_low == expected_low, f"Incorrect lower CI bound: expected {expected_low}, got {actual_low}."
        assert actual_high == expected_high, f"Incorrect upper CI bound: expected {expected_high}, got {actual_high}."

        if original_case:
            assert "Dominant Frequency Bin: 42" in content, "Incorrect dominant frequency bin in report.txt. Expected 42."
            lower = float(actual_low)
            upper = float(actual_high)
            assert 14.85 < lower < 15.00, f"Lower bound {lower} is out of expected range (14.85, 15.00)."
            assert 15.10 < upper < 15.25, f"Upper bound {upper} is out of expected range (15.10, 15.25)."

        actual_rows = parse_spectrum(SPECTRUM_PATH)
        expected_rows = parse_spectrum(expected_spectrum)
        for k, ((_, actual), (_, expected)) in enumerate(zip(actual_rows, expected_rows)):
            assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=6e-4), (
                f"Incorrect magnitude for frequency bin {k}: expected {expected}, got {actual}."
            )


def make_challenge_trace():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    dominant = rng.randint(73, 430)
    secondary = rng.randint(5, 60)
    if secondary == dominant:
        secondary = 17
    baseline = rng.uniform(8.0, 28.0)
    amplitude = rng.uniform(2.5, 5.0)
    phase = rng.uniform(-math.pi, math.pi)
    values = []
    for t in range(1024):
        value = baseline
        value += amplitude * math.sin(2.0 * math.pi * dominant * t / 1024.0 + phase)
        value += 0.35 * math.cos(2.0 * math.pi * secondary * t / 1024.0)
        value += rng.uniform(-0.7, 0.7)
        values.append(value)
    return "".join(f"{value:.6f}\n" for value in values).encode()


def test_complete_analyzer_behavior():
    compile_programs()
    with open(TRACE_PATH, "rb") as f:
        original_trace = f.read()
    try:
        with open(TRACE_PATH, "wb") as f:
            f.write(make_challenge_trace())
        run_and_check(original_case=False)

        with open(TRACE_PATH, "wb") as f:
            f.write(original_trace)
        run_and_check(original_case=True)
    finally:
        with open(TRACE_PATH, "wb") as f:
            f.write(original_trace)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
