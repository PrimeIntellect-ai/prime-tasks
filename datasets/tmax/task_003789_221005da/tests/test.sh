#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import time
import pytest

CPP_FILE = "/home/user/optimized_w1.cpp"
EXE_FILE = "/home/user/optimized_w1"
REF_CPP = "/tmp/reference_w1.cpp"
REF_EXE = "/tmp/reference_w1"

REFERENCE_SOURCE = r'''#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>

double normal_cdf(double x, double mean, double stddev) {
    return 0.5 * (1.0 + std::erf((x - mean) / (stddev * std::sqrt(2.0))));
}

int main(int argc, char **argv) {
    if (argc != 4) return 1;
    int N = std::stoi(argv[1]);
    double mean = std::stod(argv[2]);
    double stddev = std::stod(argv[3]);
    if (N <= 0 || stddev <= 0.0) return 1;

    std::mt19937 gen(42);
    std::uniform_real_distribution<double> dist(0.0, 1.0);
    std::vector<double> samples(N);
    for (double &sample : samples) sample = dist(gen);
    std::sort(samples.begin(), samples.end());

    const int M = 1000000;
    const double dx = 1.0 / M;
    double w1 = 0.0;
    std::size_t count = 0;
    for (int j = 1; j <= M; ++j) {
        double x = j * dx;
        while (count < samples.size() && samples[count] <= x) ++count;
        double ecdf = static_cast<double>(count) / N;
        double ncdf = normal_cdf(x, mean, stddev);
        w1 += std::abs(ecdf - ncdf) * dx;
    }

    std::cout << std::fixed << std::setprecision(6) << w1 << std::endl;
    return 0;
}
'''


def run_value(executable, args):
    try:
        result = subprocess.run(
            [executable, *args],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Execution failed for arguments {args}:\n{exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution timed out for arguments {args}")

    output = result.stdout.strip()
    try:
        return float(output)
    except ValueError:
        pytest.fail(f"Could not parse output as float. Output was: {output}")


def test_optimized_w1_performance_and_accuracy():
    assert os.path.isfile(CPP_FILE), f"The optimized C++ file {CPP_FILE} is missing."

    try:
        subprocess.run(
            ["g++", "-O3", CPP_FILE, "-o", EXE_FILE],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Compilation failed:\n{exc.stderr}")

    assert os.path.isfile(EXE_FILE), "Executable was not created after compilation."

    with open(REF_CPP, "w") as reference_file:
        reference_file.write(REFERENCE_SOURCE)
    try:
        subprocess.run(
            ["g++", "-O3", REF_CPP, "-o", REF_EXE],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Reference compilation failed:\n{exc.stderr}")

    fixed_args = ["50000", "0.5", "0.15"]
    start_time = time.time()
    agent_val = run_value(EXE_FILE, fixed_args)
    agent_time = time.time() - start_time

    speedup = 100.0 / agent_time
    assert speedup >= 50.0, (
        f"Speedup {speedup:.2f}x is below the 50.0x threshold "
        f"(Agent time: {agent_time:.4f}s)."
    )

    assert agent_val > 0.0, f"Wasserstein distance must be > 0.0, got {agent_val}"
    assert agent_val < 0.2, (
        f"Wasserstein distance {agent_val} is too large to be correct for "
        "U(0,1) vs N(0.5, 0.15)."
    )

    reference_val = run_value(REF_EXE, fixed_args)
    assert abs(agent_val - reference_val) <= 1e-5, (
        f"Numerical error {abs(agent_val - reference_val):.8g} exceeds 1e-5 "
        f"for arguments {fixed_args}: got {agent_val}, expected {reference_val}"
    )

    # These cases are selected only after the agent has finished, preventing a
    # fixed lookup or constant output from satisfying the numerical check.
    cases = []
    for _ in range(3):
        n = 1000 + secrets.randbelow(11001)
        mean = 0.20 + secrets.randbelow(600001) / 1000000.0
        stddev = 0.06 + secrets.randbelow(240001) / 1000000.0
        cases.append([str(n), f"{mean:.6f}", f"{stddev:.6f}"])

    for args in cases:
        actual = run_value(EXE_FILE, args)
        expected = run_value(REF_EXE, args)
        assert abs(actual - expected) <= 1e-5, (
            f"Numerical error {abs(actual - expected):.8g} exceeds 1e-5 "
            f"for arguments {args}: got {actual}, expected {expected}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
