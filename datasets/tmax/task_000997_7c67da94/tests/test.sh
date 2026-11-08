#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/reference_fit.cpp
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <random>
#include <vector>

static double best_lambda(std::vector<double> values) {
    std::sort(values.begin(), values.end());
    const int n = static_cast<int>(values.size());
    double best = 0.1;
    double best_distance = std::numeric_limits<double>::infinity();
    for (int j = 0; j <= 490; ++j) {
        const double lambda = 0.1 + j * 0.01;
        double distance = 1.0 / (12.0 * n);
        for (int i = 0; i < n; ++i) {
            const double cdf = 1.0 - std::exp(-lambda * values[i]);
            const double target = (2.0 * (i + 1) - 1.0) / (2.0 * n);
            const double d = cdf - target;
            distance += d * d;
        }
        if (distance < best_distance) {
            best_distance = distance;
            best = lambda;
        }
    }
    return best;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::ifstream in(argv[1]);
    std::vector<double> data;
    double x;
    while (in >> x) data.push_back(x);
    if (data.size() != 1000) return 3;

    const double optimum = best_lambda(data);
    const double tiny_x = 1e-8;
    const double stability = std::abs((1.0 - std::exp(-optimum * tiny_x))
                                    - (-std::expm1(-optimum * tiny_x)));

    std::mt19937 generator(42);
    std::uniform_int_distribution<int> index_distribution(0, 999);
    std::vector<double> estimates;
    estimates.reserve(500);
    for (int b = 0; b < 500; ++b) {
        std::vector<double> sample;
        sample.reserve(1000);
        for (int i = 0; i < 1000; ++i)
            sample.push_back(data[index_distribution(generator)]);
        estimates.push_back(best_lambda(std::move(sample)));
    }
    std::sort(estimates.begin(), estimates.end());

    std::cout << std::setprecision(17) << optimum << ' ' << stability;
    for (double estimate : estimates) std::cout << ' ' << estimate;
    std::cout << '\n';
    return 0;
}
REF_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
from pathlib import Path

import pytest

SOURCE = Path('/home/user/fit_dist.cpp')
DATA = Path('/home/user/data.txt')
RESULTS = Path('/home/user/results.json')
BINARY = Path('/home/user/fit_dist')
REFERENCE = Path('/tmp/reference_fit')
ORIGINAL_DATA = DATA.read_text()


def compile_programs():
    submitted = subprocess.run(
        ['g++', '-O3', '-std=c++17', str(SOURCE), '-o', str(BINARY)],
        text=True, capture_output=True, timeout=120
    )
    assert submitted.returncode == 0, 'fit_dist.cpp did not compile:\n' + submitted.stderr

    reference = subprocess.run(
        ['g++', '-O3', '-std=c++17', '/tmp/reference_fit.cpp', '-o', str(REFERENCE)],
        text=True, capture_output=True, timeout=120
    )
    assert reference.returncode == 0, 'Verifier reference failed to compile:\n' + reference.stderr


def reference_values():
    proc = subprocess.run(
        [str(REFERENCE), str(DATA)], text=True, capture_output=True, timeout=240
    )
    assert proc.returncode == 0, 'Verifier reference execution failed.'
    values = [float(v) for v in proc.stdout.split()]
    assert len(values) == 502
    return values[0], values[1], values[2:]


def load_results():
    assert RESULTS.is_file(), 'Expected /home/user/results.json to exist.'
    try:
        with RESULTS.open() as f:
            res = json.load(f)
    except json.JSONDecodeError:
        pytest.fail('/home/user/results.json is not valid JSON.')

    required_keys = {'lambda_opt', 'ci_lower', 'ci_upper', 'stability_diff'}
    for key in required_keys:
        assert key in res, f"Key '{key}' missing from results.json"
        assert isinstance(res[key], (int, float)), f"Value for '{key}' must be a number."
        assert math.isfinite(res[key]), f"Value for '{key}' must be finite."
    return res


def run_submission(input_text):
    DATA.write_text(input_text)
    if RESULTS.exists():
        RESULTS.unlink()
    proc = subprocess.run(
        [str(BINARY)], cwd='/home/user', text=True, capture_output=True, timeout=240
    )
    assert proc.returncode == 0, 'Compiled fit_dist program failed:\n' + proc.stderr
    assert DATA.read_text() == input_text, 'The program must read, not modify, data.txt.'
    return load_results()


def assert_exact_computation(res):
    expected_lambda, expected_stability, estimates = reference_values()
    assert abs(res['lambda_opt'] - expected_lambda) <= 0.0051, (
        f"lambda_opt should be the CvM grid optimum {expected_lambda}, got {res['lambda_opt']}"
    )

    # Standard percentile definitions differ slightly in interpolation/rank convention.
    # Every conventional 2.5%/97.5% result lies in these narrow neighborhoods of
    # the independently generated, sorted 500 seeded bootstrap estimates.
    lower_lo, lower_hi = estimates[11], estimates[13]
    upper_lo, upper_hi = estimates[486], estimates[488]
    eps = 1e-7
    assert lower_lo - eps <= res['ci_lower'] <= lower_hi + eps, (
        f"ci_lower does not match the 2.5th percentile of the 500 seeded estimates: "
        f"got {res['ci_lower']}, expected within [{lower_lo}, {lower_hi}]"
    )
    assert upper_lo - eps <= res['ci_upper'] <= upper_hi + eps, (
        f"ci_upper does not match the 97.5th percentile of the 500 seeded estimates: "
        f"got {res['ci_upper']}, expected within [{upper_lo}, {upper_hi}]"
    )

    stability_tolerance = max(1e-20, abs(expected_stability) * 1e-4)
    assert abs(res['stability_diff'] - expected_stability) <= stability_tolerance, (
        f"stability_diff should be {expected_stability}, got {res['stability_diff']}"
    )


def test_cpp_file_exists():
    assert SOURCE.is_file(), 'Expected C++ source file /home/user/fit_dist.cpp to exist.'


def test_compile_and_run_on_independent_input():
    compile_programs()
    rng = random.Random(8675309)
    hidden = '\n'.join(format(rng.expovariate(1.35), '.17g') for _ in range(1000)) + '\n'
    try:
        hidden_results = run_submission(hidden)
        assert_exact_computation(hidden_results)
    finally:
        # Leave the required artifact generated from the task's original data.
        DATA.write_text(ORIGINAL_DATA)
        if RESULTS.exists():
            RESULTS.unlink()
        proc = subprocess.run(
            [str(BINARY)], cwd='/home/user', text=True, capture_output=True, timeout=240
        )
        DATA.write_text(ORIGINAL_DATA)
        assert proc.returncode == 0, 'Program failed when run on the original data.'


def test_results_json_exists():
    assert RESULTS.is_file(), 'Expected /home/user/results.json to exist.'


def test_results_json_contents():
    res = load_results()

    # Independently validate all 500 seeded bootstrap draws, their percentiles,
    # the original-data optimum, and the numerical stability calculation.
    assert_exact_computation(res)

    # Preserve the original verifier's direct recomputation and assertions.
    assert DATA.is_file(), 'data.txt is missing.'
    with DATA.open() as f:
        data = [float(line.strip()) for line in f if line.strip()]
    assert len(data) == 1000, 'Expected exactly 1000 values in data.txt.'

    n = len(data)
    data_sorted = sorted(data)

    def cvm(lmbda):
        term_sum = 0.0
        for i, x in enumerate(data_sorted):
            cdf = 1.0 - math.exp(-lmbda * x)
            expected = (2 * (i + 1) - 1) / (2.0 * n)
            term_sum += (cdf - expected) ** 2
        return 1.0 / (12.0 * n) + term_sum

    lambdas = [0.1 + i * 0.01 for i in range(491)]
    best_lambda = min(lambdas, key=cvm)

    assert abs(res['lambda_opt'] - best_lambda) < 0.011, (
        f"Expected lambda_opt ~ {best_lambda}, got {res['lambda_opt']}"
    )
    assert 2.0 < res['ci_lower'] < best_lambda, (
        f"ci_lower {res['ci_lower']} out of expected range (2.0, {best_lambda})"
    )
    assert best_lambda < res['ci_upper'] < 3.0, (
        f"ci_upper {res['ci_upper']} out of expected range ({best_lambda}, 3.0)"
    )
    assert res['stability_diff'] >= 0.0, 'stability_diff should be non-negative.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
