#!/bin/bash
mkdir -p /logs/verifier

cat << 'ORACLE_EOF' > /tmp/fit_model_oracle.cpp
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>

struct Observation {
    double x1;
    double x2;
    double y;
};

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::ifstream input(argv[1]);
    if (!input) return 3;

    std::vector<Observation> observations;
    observations.reserve(100);
    for (int i = 0; i < 10; ++i) {
        for (int j = 0; j < 10; ++j) {
            double y;
            if (!(input >> y)) return 4;
            observations.push_back({static_cast<double>(i), static_cast<double>(j), y});
        }
    }
    double extra;
    if (input >> extra) return 5;

    std::mt19937 rng(42);
    std::uniform_int_distribution<int> select(0, 99);
    std::vector<double> estimates;
    estimates.reserve(1000);

    for (int b = 0; b < 1000; ++b) {
        std::vector<int> sample(100);
        for (int n = 0; n < 100; ++n) sample[n] = select(rng);

        double theta1 = 0.0;
        double theta2 = 0.0;
        for (int iteration = 0; iteration < 1000; ++iteration) {
            double gradient1 = 0.0;
            double gradient2 = 0.0;
            for (int index : sample) {
                const Observation& o = observations[index];
                const double x1_squared = o.x1 * o.x1;
                const double x2_squared = o.x2 * o.x2;
                const double residual = o.y - theta1 * x1_squared - theta2 * x2_squared;
                gradient1 += -2.0 * x1_squared * residual / 100.0;
                gradient2 += -2.0 * x2_squared * residual / 100.0;
            }
            theta1 -= 0.00001 * gradient1;
            theta2 -= 0.00001 * gradient2;
        }
        estimates.push_back(theta1);
    }

    double mean = 0.0;
    for (double estimate : estimates) mean += estimate;
    mean /= 1000.0;
    std::sort(estimates.begin(), estimates.end());
    std::cout << std::setprecision(17) << mean << ' ' << estimates[25] << ' ' << estimates[974] << '\n';
    return 0;
}
ORACLE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

CPP_PATH = "/home/user/fit_model.cpp"
DATA_PATH = "/home/user/data.txt"
RESULT_PATH = "/home/user/result.txt"
SUBMISSION_BIN = "/tmp/fit_model_submission"
ORACLE_BIN = "/tmp/fit_model_oracle"


def compile_program(source, output):
    completed = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"Failed to compile {source}:\n{completed.stderr}"


def read_result():
    assert os.path.isfile(RESULT_PATH), f"Expected results file {RESULT_PATH} does not exist."
    with open(RESULT_PATH, "r") as result_file:
        content = result_file.read().strip().split()
    assert len(content) == 3, f"Expected exactly 3 values in {RESULT_PATH}, found {len(content)}."
    try:
        values = tuple(map(float, content))
    except ValueError:
        raise AssertionError(f"Could not parse the contents of {RESULT_PATH} as 3 floating-point numbers.")
    assert all(math.isfinite(value) for value in values), "Result values must be finite."
    return values


def oracle_result():
    completed = subprocess.run(
        [ORACLE_BIN, DATA_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"Oracle failed: {completed.stderr}"
    fields = completed.stdout.strip().split()
    assert len(fields) == 3
    return tuple(map(float, fields))


def run_submission():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [SUBMISSION_BIN],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert completed.returncode == 0, f"Submitted program failed:\n{completed.stderr}"
    return read_result()


def assert_matches(actual, expected):
    for label, got, wanted in zip(("Mean_Theta1", "CI_Lower", "CI_Upper"), actual, expected):
        tolerance = max(5e-5, 2e-6 * abs(wanted))
        assert math.isclose(got, wanted, rel_tol=0.0, abs_tol=tolerance), \
            f"{label} {got} differs from computed expected value {wanted}."


def test_complete_program_behavior():
    assert os.path.isfile(CPP_PATH), f"Expected C++ source file {CPP_PATH} does not exist."
    compile_program(CPP_PATH, SUBMISSION_BIN)
    compile_program("/tmp/fit_model_oracle.cpp", ORACLE_BIN)

    with open(DATA_PATH, "rb") as data_file:
        original_data = data_file.read()
    original_result = None

    try:
        with open(DATA_PATH, "wb") as data_file:
            data_file.write(original_data)
        expected_original = oracle_result()
        actual_original = run_submission()
        assert_matches(actual_original, expected_original)

        mean_t, ci_l, ci_u = actual_original
        expected_mean = 2.49
        expected_lower = 2.42
        expected_upper = 2.55
        tolerance = 0.1
        assert math.isclose(mean_t, expected_mean, abs_tol=tolerance), \
            f"Mean Theta1 {mean_t} is not within {tolerance} of expected {expected_mean}."
        assert math.isclose(ci_l, expected_lower, abs_tol=tolerance), \
            f"CI Lower {ci_l} is not within {tolerance} of expected {expected_lower}."
        assert math.isclose(ci_u, expected_upper, abs_tol=tolerance), \
            f"CI Upper {ci_u} is not within {tolerance} of expected {expected_upper}."

        with open(RESULT_PATH, "rb") as result_file:
            original_result = result_file.read()

        challenge_rows = []
        for i in range(10):
            row = []
            for j in range(10):
                noise = (((17 * i + 11 * j) % 13) - 6) * 0.21
                value = 0.65 * i * i - 0.35 * j * j + noise
                row.append(f"{value:.4f}")
            challenge_rows.append(" ".join(row))
        with open(DATA_PATH, "w") as data_file:
            data_file.write("\n".join(challenge_rows) + "\n")

        expected_challenge = oracle_result()
        actual_challenge = run_submission()
        assert_matches(actual_challenge, expected_challenge)
    finally:
        with open(DATA_PATH, "wb") as data_file:
            data_file.write(original_data)
        if original_result is not None:
            with open(RESULT_PATH, "wb") as result_file:
                result_file.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
